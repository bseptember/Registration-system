#!/bin/bash


export oidc_host=$(hostname -I | awk '{print $1}')
export oidc_port="8443"


# Function to check network connectivity
check_connectivity() {
    while ! nc -z "$oidc_host" "$oidc_port"; do
        echo "Waiting for access to oidc @ $oidc_host:$oidc_port"
        sleep 20
    done
    # Connection is established, add provisioner and start step-ca
    step ca provisioner update keycloak --listen-address=localhost:7000
    pkill -SIGTERM -f '/usr/local/bin/step-ca'
    /usr/local/bin/step-ca --password-file $PWDPATH $CONFIGPATH
}

# Run the function in the background
check_connectivity
