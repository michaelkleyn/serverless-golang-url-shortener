package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
	"github.com/gofrs/uuid"
)

// constant values that won't change
const (
	// BaseURL used for "shortening" -- should be the one used in API Gateway/terraform
	// NOTE:  update the value of this constant to match the domain you're using in your AWS account
	BaseURL = "https://mkleyn.org"
	//BaseURL = "https://<domain_name>"
	// ShortURLTable value needs to match the name used in terraform for DynamoDB table creation
	ShortURLTable = "UrlShortenerTable"
	// Region is us-east-1 by default
	Region = "us-east-1"
)

// Request struct used in unmarshaling in order to
// parse `url` field from request input
type Request struct {
	URL string `json:"url"`
}

// Item struct to hold the info to be written
// to the `url-shortener`DynamoDB table
type Item struct {
	ID       string `json:"Id"`
	LongURL  string `json:"LongUrl"`
	HitCount int    `json:"HitCount"`
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	requestBody := Request{}
	// unmarshal input data to parse 'url' input data field
	if err := json.Unmarshal([]byte(request.Body), &requestBody); err != nil {
		return events.APIGatewayProxyResponse{Body: "Error during unmarshalling", StatusCode: 500}, err
	}
	// Start DynamoDB session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(Region),
	})
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "Error during AWS client instantiation", StatusCode: 500}, err
	}
	// instantiate AWS DyanmoDB client
	svc := dynamodb.New(sess)

	// generate unique identifier for new URL, based on random numbers
	uuid, err := uuid.NewV4()
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "Failed to generate UUID for new short URL", StatusCode: 500}, err
	}
	// take just the first five characters from the generated uuid in order to keep urls short
	shortURLId := uuid.String()[0:5]

	// before creating new item in DynamoDB table,
	// verify that the shortUrlId generated is unique and doesn't exist in DynamoDB
	params := &dynamodb.GetItemInput{
		Key: map[string]*dynamodb.AttributeValue{
			"Id": {
				S: aws.String(shortURLId),
			},
		},
		TableName: aws.String(ShortURLTable),
	}

	// perform a GetItem to see if the short url unique id already exists
	resp, err := svc.GetItem(params)
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "An error was encountered reading from DynamoDB.", StatusCode: 500}, err
	}

	// sanity check to ensure no DynamoDB Items exist with an Id that matches the generated one
	if len(resp.Item) > 0 {
		return events.APIGatewayProxyResponse{Body: "The generated short url id already exists in DynamoDB--please try creating a shortened url again.", StatusCode: 500}, err
	}

	// create Item object that will be used in PutItem DynamoDB call
	item := Item{
		ID:       shortURLId,
		LongURL:  requestBody.URL,
		HitCount: 0,
	}
	// prepare DynamoDB input to write new Item to the table
	av, err := dynamodbattribute.MarshalMap(item)
	input := &dynamodb.PutItemInput{
		Item:      av,
		TableName: aws.String(ShortURLTable),
	}
	// Put Item in DynamoDB table
	_, err = svc.PutItem(input)
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "Failed to write item to DynamoDB table", StatusCode: 500}, err
	}

	// construct new shortened URL to return to the user
	newURL := fmt.Sprintf("%s/%s", BaseURL, shortURLId)
	return events.APIGatewayProxyResponse{Body: newURL, StatusCode: 200}, nil
}

func main() {
	// execute the lambda!
	lambda.Start(handleRequest)
}
