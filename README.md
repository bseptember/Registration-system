# Registration-system

Backend registration server system for clients. The following is used in this setup.

Keycloak, LDAP, and local user registrations, and rabbitmq

## Prerequisites

Operating System: Ubuntu (any version)

Docker: Docker Engine & Docker Compose


## Quick start

Generates some self-signed certificates, so that authentication involving keycloak can more realistically
involve TLS (within the docker network). 

1. Copy/Clone the repo.
2. Give permission using chmod to the directory
3. Change REMOTE_CLIENT_IP in the start.sh file to your client IP address.

```
sudo chmod -R 777 Registration-system 
./start.sh
```

You'll be asked whether to overwrite the rootCA if it exists.
The root CA certificate will be in `./rootCA.crt`.


this will generate a .env file as well, enter local ip address if this LOCAL_IP="" is blank,
then run the script again.


```
oidc
```

Keycloak

username: admin

password: admin

https://localhost:8443

http://localhost:8080


you can add custom keycloak providers in oidc/providers

```
./ldap_mock/config_ldap
```

You should get a bunch of lines like `adding new entry "uid=55532dde-dfd6-4811-8ceb-518631f552ee,dc=example,dc=org"`.

When Keycloak up and running (when `docker-compose logs oidc_kc` shows `Admin console listening`), add the realm and users


```
./ldap_mock/update_ldap
```

Use this to update the mock users. Alternatively, go to https://localhost:6443


```
rabbitmq
```

https://localhost:15671

http://localhost:15672

For a rabbit_admin account:

Go to the following url, click log on. Register a new account. Login to Keycloak, then navigate to the Realm and Users. Select the user you just created and go to the Role Mapping tab. Assign roles, rabbitmq. read, write and configure as well as tag:management.


## Step ca

use the following command to edit the --listen ip address

docker exec -it stepca sh -c '/home/oidc.sh'

## Allowing user registration

Go to the "Realm Settings" and under the "Login" tab, enable user registration.

## Adding the LDAP

Under "User Federation", add an LDAP provider. 

We're going to set the following parameters:

*	enabled: ON
*	console display name: _whatever you like, 'ldap' is fine_
*	vendor: Other
*	Connection URL: ldap://{IP_ADDR}:3890
*	Bind Type: simple
*	Bind DN: `cn=admin,dc=example,dc=org`
*	Bind Credential: `admin`
*	edit mode: READ_ONLY
*	Users DN: `dc=example,dc=org`
*	username LDAP attribute: mail
*	RDN LDAP attribute: uid
*	UUID LDAP attribute: uid
*	User Object Classes: inetOrgPerson
*	User LDAP Filter: _leave blank_
*	Search Scope: One Level
*	import users: OFF
*	sync registrations: OFF

That should be enough; hit "save" and then "Test Connection".  Then hit "Synchronize all users".


## Useful TLS commands for openssl

Initiate a server connection using the certificates provided in the certs. After running the quick start command, stop or remove all containers before attempting this or use a different port.

For the server:

```
openssl s_server -accept 8443 -cert rabbitmq.crt -key rabbitmq.key -CAfile intermediate_ca.crt
```

For the client:

```
openssl s_client -connect localhost:8443 -cert custom.crt -key custom.key -CAfile intermediate_ca.crt -verify 8
```

The output will give you information regarding the certificate validity. Anything other than Verify return code: 0 (ok) will indicate a faulty certificate.
