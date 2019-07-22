# Docksal Sandbox Server

Turn-key templates to launch a Docksal Sandbox Server in the cloud.

## Launch a sandbox server

Follow the instructions for supported cloud providers:

- [Amazon Web Services](./aws-cloudformation)
- [Google Cloud Platform](./gcp-deployment-manager)

When done, come back and continue reading.

<a name="server-access"></a>
## Access the sandbox server

SSH into the server as the `build-agent` user:

    ssh -i <ssh-private-key> build-agent@<external-ip>

**Note**: `<ssh-private-key>` and `<external-ip>` are values from the server provisioning step.

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

Set the following variables in your CI project/organization build settings to tell `ci-agent` how to access 
the provisioned sandbox server:

- `DOCKSAL_HOST_IP` - the external IP of the sandbox server obtained in the previous steps (`<external-ip>`).
- `DOCKSAL_HOST_SSH_KEY` - copy it from the output of `cat <ssh-private-key> | base64`

**Note**: `<ssh-private-key>` and `<external-ip>` are values from the server provisioning step.

For more information on `ci-agent` configuration see https://github.com/docksal/ci-agent

### Advanced CI build settings

See [Project configuration](https://github.com/docksal/ci-agent#project-configuration) docs for more details on 
`docksal/ci-agent` configuration options.
