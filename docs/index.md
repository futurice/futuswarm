
# Introducing Futuswarm

Futuswarm is a Docker Swarm installation on Amazon Web Services (AWS) that provides a minimalistic PaaS (~Heroku) experience with containerized deployments onto a wildcard domain.

This is an open source labor that helped Futurice IT become "Cloud Ready" [Making an Open-Source PaaS](https://futurice.com/blog/making-an-open-source-paas). A combination of AWS with Docker Swarm in a pure way, keeping state outside of the Swarm itself. This means futuswarm can be taken into use without the fear of data loss. Commands for disaster recovery and backups are built-in. The codebase is easy to hack.

*Core goals*
* Use AWS -resources and Docker Swarm as-is without developing any additional components that would need ongoing maintenance
* Keep state (configuration, secrets, docker images) in cloud services like S3 and Docker Hub
* Make the Chaos Monkey sad

*What is included*
* AWS configuration
    * Virtual Private Cloud (VPC)
        * Private network for internal traffic
        * Internet Gateway (IG) for outgoing traffic
        * Subnets
    * Security Group for firewall rules
        * Allow internal traffic
        * Allow SSH access
    * EC2 Key Pairs
        * SSH access (root)
    * Amazon Certificate Manager (ACM)
        * Wildcard domains for private/public endpoints
    * VPC Peering (optional)
    * Elastic Compute Cloud (EC2) instances
        * Create manager and worker instances
        * Configuration for futuswarm client/server communication
    * Elastic Load Balancer (ELB)
        * Allow HTTP, HTTPS (using generated ACM certificate) access
        * Main entry to EC2 instances
* Docker installation
    * Allows experimental features
* Access Control List (ACL)
    * Usage rules for CLI (owners, admins)
* [REX-Ray](https://rexray.thecodeteam.com/) installation
    * Allows persistent storage using Elastic Block Store (EBS)
* System Security Services Daemon (SSSD) -- TBA
    * Allow access based on existing LDAP users/groups
* Relational Database Service (RDS) installation
    * PostgreSQL installation allows adding a database to each service
    * Enforces server/client ACLs
* Client/Server (CLI) installation
    * Developer-friendly CLI for interacting with the Docker Swarm
    * Allows PaaS -like features
* [Docker Swarm](https://docs.docker.com/engine/swarm/) installation
    * 1 manager
    * N workers
* SSO Proxy
    * Apache handles all ELB traffic to check it satisfies access criteria (eg. authenticated user)
    * Forwards traffic to Docker Flow Proxy (DFP)
* [Docker Flow Proxy](https://github.com/vfarcic/docker-flow-proxy) (DFP)
    * Docker Swarm service discovery using Docker API
    * Service configuration (domains, ports) with HAProxy
    * Handles forwarded traffic from SSO Proxy
    * Forwards traffic to the actual Docker Swarm services
* [Secrets](https://github.com/futurice/secret)
    * Docker configuration (ENV) and Docker secrets handled externally
    * Encrypted using Key Management Service (KMS)
    * Storage in S3
* Cron jobs
    * Backups of running service configuration
    * Backups of running images
* Futuswarm containers
    * Mainpage containing usage instructions
    * Health checks
* Tested using BATS
    * Local Docker Swarm for unit testing

*What is NOT (yet) included*
* Monitoring for High Availability (HA)
* Centralized Logging

Interested? Want to contribute? See [futuswarm github](https://github.com/futurice/futuswarm) for the installer and further details.
