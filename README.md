Spring Cloud Native with Docker Compose
========================================

Prerequisites:
    
    - aws account
    - aws cli (with admin rights)
    - rancher cli

To build locally:

    `./gradlew build buildDocker`

To run:

    `cd docker`
    
    `docker-compose up`

To deploy the rancher aws environment:

    Make sure you have:
    - a key pair
    - an elastic ip

    Run:
     `rancher-aws-env-setup.sh -k AWS_PUBLIC_KEY_NAME -i ELASTIC_IP_ADDRESS`

To check the Rancher server logs:

    `ssh -i AWS_PUBLIC_KEY_NAME ubuntu@ELASTIC_IP_ADDRESS`
    `docker ps`
    `docker logs -f DOCKER_IMAGE_ID`

To open Rancher ui:

    `http://ELASTIC_IP_ADDRESS:8080/`

To create the Jenkins environment:

    - In the Rancher UI enable Access Control using GitHub
    - In the Rancher UI create an Account API Key http://13.55.223.157:8080/env/1a5/api/keys
    - Run the command `rancher config` and set the url, access key, and secret key
    - In AWS create an Access Key using the 'region-rancher-user' where the 'region' is the
      AWS region you are deploying into
      (http://docs.aws.amazon.com/general/latest/gr/managing-aws-access-keys.html)
    - Run:

      `rancher-ci-setup.sh -a YOUR_ACCESS_KEY -s YOUR_SECRET_KEY`
