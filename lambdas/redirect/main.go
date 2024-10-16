package main

import (
	"net/http"
	"strconv"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
)

const (
	// ShortURLTable needs to match the name used in terraform
	ShortURLTable = "UrlShortenerTable"
	// Region is us-east-1 by default
	Region = "us-east-1"
)

// Item struct supports the Get/Put/Update DynamoDB operations
type Item struct {
	ID       string `json:"Id"`
	LongURL  string `json:"LongUrl"`
	HitCount int    `json:"HitCount"`
}

func handleRequest(request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// retrieve 'id' parameter from url that a GET request was performed with
	shortURLId, _ := request.PathParameters["id"]
	// Start DynamoDB session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(Region),
	})
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "Error during AWS client instantiation", StatusCode: 500}, err
	}
	// instantiate AWS DynamoDB client
	svc := dynamodb.New(sess)

	// attempt to fetch relevant item from DyanmoDB, using the 'id' provided in the GET request
	// create GetItemInput and then perform a GetItem to see if the short url unique 'id' exists
	params := &dynamodb.GetItemInput{
		Key: map[string]*dynamodb.AttributeValue{
			"Id": {
				S: aws.String(shortURLId),
			},
		},
		TableName: aws.String(ShortURLTable),
	}
	// perform GetItem call
	resp, err := svc.GetItem(params)

	if err != nil {
		return events.APIGatewayProxyResponse{Body: "An error was encountered reading from DynamoDB.", StatusCode: 500}, err
	}

	if len(resp.Item) == 0 {
		return events.APIGatewayProxyResponse{Body: "This short url does not correspond to a longer URL.", StatusCode: 404}, err
	}

	// unmarshal response from DynamoDB
	item := Item{}
	if err := dynamodbattribute.UnmarshalMap(resp.Item, &item); err != nil {
		return events.APIGatewayProxyResponse{StatusCode: 500}, err
	}

	// increment the HitCount attribute and perform an UpdateItem to increment HitCount
	err = updateHitCountAttribute(svc, &item)
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: 500}, err
	}

	// redirect to long URL
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusPermanentRedirect,
		Headers: map[string]string{
			"location": item.LongURL,
		},
	}, nil
}

// for ease of readability, extract updateItem code for HitCount field
// into seperate function, which returns an error or nil
func updateHitCountAttribute(svc *dynamodb.DynamoDB, item *Item) error {
	item.HitCount++
	input := &dynamodb.UpdateItemInput{
		ExpressionAttributeValues: map[string]*dynamodb.AttributeValue{
			":hitCount": {
				N: aws.String(strconv.Itoa(item.HitCount)),
			},
		},
		TableName: aws.String(ShortURLTable),
		Key: map[string]*dynamodb.AttributeValue{
			"Id": {
				// primary key on the UrlShortener Table is the ID struct field
				S: aws.String(item.ID),
			},
		},
		ReturnValues:     aws.String("UPDATED_NEW"),
		UpdateExpression: aws.String("SET HitCount = :hitCount"),
	}

	// perform update in DynamoDB
	_, err := svc.UpdateItem(input)
	return err
}

func main() {
	// execute the lambda!
	lambda.Start(handleRequest)
}
