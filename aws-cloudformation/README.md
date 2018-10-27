# Docksal Sandbox Server - AWS CloudFormation

This is a Docksal Sandbox Server template for AWS CloudFormation.

AWS CloudFormation is a service that helps you model and set up your Amazon Web Services resources so that you
can spend less time managing those resources and more time focusing on your applications that run in AWS.
You create a template that describes all the AWS resources that you want (like Amazon EC2 instances or Amazon RDS
DB instances), and AWS CloudFormation takes care of provisioning and configuring those resources for you. You
don't need to individually create and configure AWS resources and figure out what's dependent on what;
AWS CloudFormation handles all of that. 

For an overview of AWS CloudFormation, see the [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html.)

## Quick setup (using CloudFormation web UI)

If you have an existing AWS account (with billing and an SSH key pair), just click on the button below!

[![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=docksal-sandbox-server&templateURL=https://s3.us-east-2.amazonaws.com/docksal-aws-templates/sandbox-server/stable/template.yaml)

You will be prompted for:

- Instance type
- SSH key name

Once provisioned, the IP address of the server will be printed in the **Outputs** section in CloudFormation (`<external-ip>`). 

Note: You will need the key you selected to access the sandbox server in further steps (`<ssh-private-key>`).

You can now proceed to [Access the sandbox server](/README.md#server-access) 

Note: For manual setup steps (using console tools), see [Manual setup](#manual)


<a name="manual"></a>
## Manual setup (using console tools)

Step-by-step manual setup instructions using aws cli and provisioning scripts. 

### Initial setup on AWS

1. Log in or create a new AWS account.

1. [Create Access Keys for Your AWS Account Root User](https://docs.aws.amazon.com/general/latest/gr/managing-aws-access-keys.html). Keep these keys in a safe place!

1. [Create SSH key pair or import existing key pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair).
 
    **Note**: You can also use the `ssh-key-create` / `ssh-key-import` scripts in this repo (see instructions below).

1. Install `aws` cli tool locally (for Ubuntu run `sudo apt install awscli`)

1. Clone this repo

1. Configure `aws` cli tool to use your account

    ```
    aws configure
    ```

### Create SSH key pair and import the key to AWS EC2

**Note**: Skip this step, if you already have an existing SSH key pair or created one earlier in this process.

Navigate to the `aws-cloudformation` folder:

    cd aws-cloudformation

Execute:

    ./scripts/ssh-key-create <keyname> - this will create new SSH key pair in your ~/.ssh directory
    ./scripts/ssh-key-import <keyname> - this will import a local SSH key pair to all AWS EC2 regions

### Deploy the sandbox server

Navigate to the `aws-cloudformation` folder:

    cd aws-cloudformation

Create template ready for deploy:

    ./scripts/bash2yaml startup.sh - will create template file template.yaml with startup.sh merged in it
    ./scripts/bash2json startup.sh - will create template file template.json with startup.sh merged in it

By default create-stack script uses `template.yaml`. If you want using template in json format you can edit
`create-stack` script and change the value of the `template_file` variable to the preferred template format.

Launch the deployment:

    ./create-stack <stack-name> <keyname> [<instancetype>]

In the output of the command you'll find the server public IP address:

    InstanceIPAddress <external-ip>

You can now proceed to [Access the sandbox server](/README.md#server-access)

### Delete the sandbox server

To delete the deployment and all the resources that were created:

    ./delete-stack <stack-name>
