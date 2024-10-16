# URL Shortener with AWS Lambda, Terraform, and Go

## Introduction

Welcome to the URL Shortener project! This application demonstrates how to build a scalable, serverless URL shortening service using AWS Lambda, Terraform, and Go. It leverages Amazon's serverless infrastructure to provide a cost-effective and highly available solution.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Key Components](#key-components)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

## Features

- **Serverless Architecture**: Utilizes AWS Lambda and API Gateway for a fully serverless setup.
- **Infrastructure as Code**: Managed with Terraform for reproducible deployments.
- **Written in Go**: High-performance backend with Go's efficiency and concurrency.
- **Scalable and Cost-Effective**: Automatically scales with demand and follows a pay-per-use model.
- **Custom Domain Support**: Configured with AWS Route53 and ACM for a custom domain and SSL.
- **DynamoDB Integration**: Stores URL mappings and hit counts in a NoSQL database.
- **API Gateway Integration**: Manages RESTful API endpoints for shortening and redirecting URLs.

## Architecture

The application consists of two main AWS Lambda functions:

- **Shorten Function (shorten)**: Handles `POST` requests to create shortened URLs.
- **Redirect Function (redirect)**: Handles `GET` requests to redirect users to the original URL.

These functions are exposed via AWS API Gateway and interact with a DynamoDB table to store and retrieve URL data.

## Prerequisites

- **AWS Account**: An active AWS account with necessary permissions.
- **Terraform**: Installed Terraform v0.12 or later.
- **Go**: Installed Go 1.13 or later.
- **AWS CLI**: Installed and configured with your AWS credentials.
- **Domain Name**: Access to a domain name managed via AWS Route53.

## Installation

### 1. Clone the Repository

```bash
   git clone https://github.com/yourusername/url-shortener.git
   cd url-shortener
```

### 2. Build the Lambda Functions

Compile the Go code and package it for deployment.

#### Shorten Function

```bash
  cd lambdas/shorten
  GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
  zip main.zip bootstrap
  cd ../../
```

#### Redirect Function

```bash
  cd lambdas/redirect
  GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
  zip main.zip bootstrap
  cd ../../
```

### 3. Initialize and Deploy with Terraform

#### Initialize Terraform

```bash
  terraform init
```

#### Deploy the Infrastructure

```bash
  terraform apply
```

Review the plan and type `yes` to confirm the deployment.

## Usage

### Shorten a URL

Make a `POST` request to the `/shorten` endpoint with the URL you wish to shorten.

```bash
curl -X POST \
 'https://yourdomain.com/shorten' \
 --header 'Content-Type: application/json' \
 --data-raw '{"url": "https://example.com/long-url"}'
```

#### Response:

```bash
https://yourdomain.com/abcde
```

### Redirect to the Original URL

Navigate to the shortened URL in your browser or via a GET request.

```bash
curl -L 'https://yourdomain.com/abcde'
```

You will be redirected to the original long URL.

## Project Structure

```bash
├── lambdas
│ ├── redirect
│ │ ├── main.go
│ │ ├── go.mod
│ │ ├── go.sum
│ │ ├── bootstrap
│ │ └── main.zip
│ └── shorten
│ ├── main.go
│ ├── go.mod
│ ├── go.sum
│ ├── bootstrap
│ └── main.zip
├── terraform
│ ├── main.tf
│ ├── provider.tf
│ ├── variables.tf
│ └── backend.tf
├── README.md
└── LICENSE
```

- lambdas: Contains the Go source code and compiled binaries for the Lambda functions.
- terraform: Contains Terraform configuration files for infrastructure deployment.

### Key Components

#### AWS Lambda Functions

- Shorten Function: Receives a long URL and generates a unique short code, storing the mapping in DynamoDB.
- Redirect Function: Retrieves the original URL based on the short code and redirects the user.

#### DynamoDB Table

- UrlShortenerTable: Stores URL mappings with fields for Id, LongUrl, and HitCount.

#### Terraform Configuration

Manages AWS resources including Lambda functions, API Gateway, DynamoDB, Route53 records, and ACM certificates.

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a new branch:`git checkout -b feature/your-feature-name`
3. Commit your changes:`git commit -am 'Add new feature'`
4. Push to the branch:`git push origin feature/your-feature-name`
5. Submit a pull request.

## License

This project is licensed under the MIT License.
