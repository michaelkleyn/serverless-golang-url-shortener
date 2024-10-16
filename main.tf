locals {
  domain_name      = "mkleyn.org" # e.g. example.com
  api_gateway_name = "UrlShortener"
}

##########################################
##########################################
# Route53, Certificate Manager Resources #
##########################################
##########################################
data "aws_route53_zone" "domain" {
  name         = local.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "domain" {
  domain_name       = local.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "domain" {
  for_each = {
    for dvo in aws_acm_certificate.domain.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain.zone_id
}

resource "aws_acm_certificate_validation" "domain" {
  certificate_arn         = aws_acm_certificate.domain.arn
  validation_record_fqdns = [for record in aws_route53_record.domain : record.fqdn]
}

# A record is necessary to route traffic from Route53 to API Gateway
resource "aws_route53_record" "alias" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.api.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.api.cloudfront_zone_id
    evaluate_target_health = false
  }
}

###########################################
###########################################
# API Gateway, Lambda, and IAM  Resources #
###########################################
###########################################
#
# API Gateway
resource "aws_api_gateway_domain_name" "api" {
  domain_name     = local.domain_name
  certificate_arn = aws_acm_certificate_validation.domain.certificate_arn

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = local.api_gateway_name
}

resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.redirect.id,
      aws_api_gateway_method.redirect.id,
      aws_api_gateway_integration.redirect.id,

      aws_api_gateway_resource.shorten.id,
      aws_api_gateway_method.shorten.id,
      aws_api_gateway_integration.shorten.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

resource "aws_api_gateway_base_path_mapping" "api" {
  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api.stage_name
  domain_name = aws_api_gateway_domain_name.api.domain_name
}

// ****************************
// * BEGIN "/shorten" => POST *
// ****************************
resource "aws_api_gateway_resource" "shorten" {
  path_part   = "shorten"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}
resource "aws_api_gateway_method" "shorten" {
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_resource.shorten.id
  http_method          = "POST"
  request_validator_id = aws_api_gateway_request_validator.shorten.id
  authorization        = "NONE"
  request_models = {
    "application/json" = aws_api_gateway_model.shorten.name
  }
}
resource "aws_api_gateway_model" "shorten" {
  rest_api_id  = aws_api_gateway_rest_api.api.id
  name         = "ShortenUrlPost"
  description  = "JSON schema for validating input for url-shortening POST request"
  content_type = "application/json"

  schema = <<EOF
{
	"$schema": "http://json-schema.org/draft-04/schema#",
	"title": "POST /shorten input validating model",
	"description": "JSON schema for validating input for url-shortening POST request",
	"type": "object",
	"properties": {
		"url": {
			"type": "string"
		}
	},
	"required": ["url"]
}
EOF
}
resource "aws_api_gateway_request_validator" "shorten" {
  name                  = "url-shorten-post"
  rest_api_id           = aws_api_gateway_rest_api.api.id
  validate_request_body = true
}
resource "aws_api_gateway_integration" "shorten" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.shorten.id
  http_method             = aws_api_gateway_method.shorten.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.shorten.invoke_arn
}
resource "aws_api_gateway_method_response" "shorten" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.shorten.id
  http_method = aws_api_gateway_method.shorten.http_method
  status_code = "200"
}
resource "aws_lambda_permission" "shorten" {
  statement_id  = "AllowShortenUrlExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shorten.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.shorten.http_method}${aws_api_gateway_resource.shorten.path}"
}
// **************************
// * END "/shorten" => POST *
// **************************

// ************************
// * BEGIN "/{id}" => GET *
// ************************
resource "aws_api_gateway_resource" "redirect" {
  path_part   = "{id}"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}
resource "aws_api_gateway_method" "redirect" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "redirect" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.redirect.id
  http_method             = aws_api_gateway_method.redirect.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.redirect.invoke_arn
}
resource "aws_api_gateway_method_response" "redirect" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.redirect.id
  http_method = aws_api_gateway_method.redirect.http_method
  status_code = "200"
}
resource "aws_lambda_permission" "redirect" {
  statement_id  = "AllowRedirectUrlExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.redirect.http_method}${aws_api_gateway_resource.redirect.path}"
}
// ************************
// * END "/{id}" => GET *
// ************************

# Lambdas
resource "aws_lambda_function" "shorten" {
  filename      = "lambdas/shorten/main.zip"
  function_name = "ShortenUrl"
  role          = aws_iam_role.role.arn
  # https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-from-the-go1-x-runtime-to-the-custom-runtime-on-amazon-linux-2/
  # when using the provided.al2 runtime, the executable name must be 'bootstrap'
  handler = "bootstrap"
  # https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-from-the-go1-x-runtime-to-the-custom-runtime-on-amazon-linux-2/
  runtime          = "provided.al2" # support for the go1.x runtime is ending
  source_code_hash = filebase64sha256("lambdas/shorten/main.zip")
}

resource "aws_lambda_function" "redirect" {
  filename      = "lambdas/redirect/main.zip"
  function_name = "RedirectUrl"
  role          = aws_iam_role.role.arn
  # https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-from-the-go1-x-runtime-to-the-custom-runtime-on-amazon-linux-2/
  # when using the provided.al2 runtime, the executable name must be 'bootstrap'
  handler = "bootstrap"
  # https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-from-the-go1-x-runtime-to-the-custom-runtime-on-amazon-linux-2/
  runtime          = "provided.al2" # support for the go1.x runtime is ending
  source_code_hash = filebase64sha256("lambdas/redirect/main.zip")
}

# IAM
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name               = "url_shortener_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "dynamodb_rw" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [
      aws_dynamodb_table.url_table.arn,
    ]
  }
}

resource "aws_iam_policy" "dynamodb_rw" {
  name        = "dynamodb_read_write"
  description = "A policy to allow lambda to read-write from/to DynamoDB"
  policy      = data.aws_iam_policy_document.dynamodb_rw.json
}

resource "aws_iam_role_policy_attachment" "dynamodb_rw_att" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.dynamodb_rw.arn
}

#####################
#####################
# DynamoDB Resource #
#####################
#####################
resource "aws_dynamodb_table" "url_table" {
  name         = "UrlShortenerTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Id"

  attribute {
    name = "Id"
    type = "S"
  }
  # Note:  below are additional attributes that the Go lambdas will write/read
  # attribute {
  #   name = "LongUrl"
  #   type = "S"
  # }
  # attribute {
  #   name = "HitCount"
  #   type = "N"
  # }
}
