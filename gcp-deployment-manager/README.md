# Docksal Sandbox Server - GCP Deployment Manager

This is a Docksal Sandbox Server template for Google Cloud Deployment Manager.

Google Cloud Deployment Manager is an infrastructure management service that makes it simple to create, deploy, 
and manage Google Cloud Platform resources. With Deployment Manager, you can create a static or dynamic template 
that describes the configuration of your Google Cloud environment and then use Deployment Manager to create these 
resources as a single deployment.

For an overview of Deployment Manager, see https://cloud.google.com/deployment-manager/docs.

## Initial setup on GCP

1. Select or create a Cloud Platform project, [from the Manage Resources page](https://console.cloud.google.com/cloud-resource-manager).

1. [Enable billing](https://support.google.com/cloud/answer/6293499#enable-billing).

1. [Enable the Deployment Manager and Compute APIs](https://console.cloud.google.com/flows/enableapi?apiid=deploymentmanager,compute_component).

1. Clone this repo

    Clone this repository locally or with [Cloud Shell](https://cloud.google.com/shell/).
    With Cloud Shell, you can manage your GCP project and resources without installing anything.

    [![Open in Cloud Shell](http://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/open?git_repo=https%3A%2F%2Fgithub.com%2Fdocksal%2Fsandbox-server&page=editor)

1. Configure `gcloud` tool to use your project. Replace `<project-id>` with the project ID

    gcloud config set project <project-id>

## Deploy the sandbox server

Navigate to the `gcp-deployment-manager` folder:

    cd gcp-deployment-manager

Launch the deployment:

    gcloud deployment-manager deployments create docksal-sandbox-server --config config.yaml

In the output of the command you'll find the server public IP address:

    OUTPUTS  VALUE
    ip       <external-ip>

There is a startup script that will do server provisioning. It will take 2-5 minutes from this point.

## Access the sandbox server

SSH into the server and switch to the `build-agent` user:

    gcloud compute ssh docksal-sandbox-server-vm
    sudo su - build-agent

Docksal is installed under the `build-agent` user account on the server. Sandbox builds MUST run as this user.

Sandbox builds path: `/home/build-agent/builds`

Sandbox build URLs:

    http://<sandbox-vhost>.<external-ip>.nip.io
    https://<sandbox-vhost>.<external-ip>.nip.io

## Launch a sample sandbox

As the `build-agent` user on the server:

    cd ~/builds
    fin project create

Follow the project wizard instructions.

You will get an "internal" URL for the sandbox in the end. Add the `<external-ip>.nip.io` prefix to it to access it 
externally, e.g.:

    http://myproject.docksal => http://myproject.docksal.<external-ip>.nip.io

## Set up the CI connection

The sandbox server is controlled over SSH by a `ci-agent` (`docksal/ci-agent`) container, which runs your CI builds.

    CI => docksal/ci-agent container => SSH => Docksal Sandbox Server

To give `ci-agent` access to the sandbox server over SSH, you'll need a SSH key pair.

Generate one like this:

    ssh-keygen -t ecdsa -f ~/.ssh/docksal-sandbox -C build-agent@docksal-sandbox

### Configure public SSH key in your GCP project

View and copy the public key:

    cat ~/.ssh/docksal-sandbox.pub

Use the copied string to set a [project-wide](https://cloud.google.com/compute/docs/instances/adding-removing-ssh-keys#project-wide) public SSH key on GCP.

### Configure CI project settings

Set the following variables in the project build settings in your CI:

- `DOCKSAL_HOST_IP` - the external IP of the sandbox server obtained in the previous steps (`<external-ip>`).
- `DOCKSAL_HOST_SSH_KEY` - copy it from the output of `cat ~/.ssh/docksal-sandbox | base64`
- `DOCKSAL_HOST_USER` - `build-agent`
- `REMOTE_BUILD_BASE` - `/home/build-agent/builds`

For more information on `ci-agent` configuration see https://github.com/docksal/ci-agent

## Configure CI build settings

See [Project configuration](https://github.com/docksal/ci-agent#project-configuration) docs.

## Delete the sandbox server

To delete the deployment and all the resources that were created:

    gcloud deployment-manager deployments delete docksal-sandbox-server
