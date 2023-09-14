# Keycloak, LDAP, and local user registrations, and rabbitmq

TODO: add verify and share tabs in account console

## Quick start

Generates some self-signed certificates, so that authentication involving keycloak can more realistically
involve TLS (within the docker network)

```
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

TODO: edit rabbitmq.conf to include certificates


## Allowing user registration

Go to the "Realm Settings" and under the "Login" tab, enable user registration.

## Adding the LDAP

Under "User Federation", add an LDAP provider. 

We're going to set the following parameters:

* enabled: ON
* console display name: _whatever you like, 'ldap' is fine_
* import users: OFF
* edit mode: READ_ONLY
* sync registrations: OFF
* vendor: Other
* username LDAP attribute: mail
* RDN LDAP attribute: uid
* UUID LDAP attribute: uid
* User Object Classes: inetOrgPerson
* Connection URL: ldap://ldap:3890
* Users DN: `dc=example,dc=org`
* Custom User LDAP Filter: _leave blank_
* Search Scope: One Level
* Bind Type: simple
* Bind DN: `cn=admin,dc=example,dc=org`
* Bind Credential: `admin`

That should be enough; hit "save" and then "Test Connection".  Then hit "Synchronize all users".
