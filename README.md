This script creates PowerDNS server with MariaDB backend

The server can be managed with native PowerDNS API via TLS-secure connection only from 91.226.31.0/24 source addresses
```
curl https://raw.githubusercontent.com/natalka1122/test-i7/master/main.sh -o main.sh
chmod +x main.sh
./main.sh
```
After script execution passwords, diagnostics and check commands will be printed

Created by natalka1122

TODO list 
- To be able to run the script several times (where should I store passwords?)
- Create letsencrypt certificate using sslip.io service
- Work with environment variables instead of hardcode