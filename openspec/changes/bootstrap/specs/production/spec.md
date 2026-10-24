# Production — delta for bootstrap

## ADDED Requirements

### Requirement: Single HTTPS origin

Production SHALL serve the site on one HTTPS address: the default domain of a CloudFront distribution, in account `685562352363`, region `eu-west-1`.
Requests to `/api/*` MUST reach the API through the load balancer, and CloudFront MUST NOT cache them.
Every other path SHALL be served from the private web bucket.

#### Scenario: Page and API on one address

- **WHEN** a browser opens `https://<id>.cloudfront.net/`
- **THEN** it receives the web page from the bucket
- **AND** the API answers `https://<id>.cloudfront.net/api/health`, never from a cache

#### Scenario: Plain HTTP

- **WHEN** a browser opens the site over `http://`
- **THEN** CloudFront redirects it to `https://`

### Requirement: Network isolation

Each production component MUST accept traffic only from the component in front of it:

- the load balancer, only from CloudFront's origin-facing prefix list;
- the API tasks, only from the load balancer, on port 8080;
- the database, only from the API tasks, on port 5432.

The database subnets MUST have no route to the internet, and the database MUST NOT be publicly accessible.
Only the CloudFront distribution SHALL be able to read the web bucket.

#### Scenario: Direct access refused

- **WHEN** a client other than the component in front of it calls the load balancer, an API task or the database
- **THEN** the security groups refuse the connection

#### Scenario: Bucket not public

- **WHEN** a client reads the web bucket without going through CloudFront
- **THEN** S3 refuses the request

### Requirement: Destroy-ready resources

One `terraform destroy` SHALL delete every production resource, with no manual step, and production SHALL be re-creatable right after. In particular:

- the database MUST have no deletion protection, no final snapshot and no automated backups, and RDS MUST manage its password;
- the image registry and the web bucket MUST be deleted together with their contents;
- no resource SHALL use a name or key that AWS keeps reserved after deletion, such as a named secret or a customer-managed KMS key.

#### Scenario: Destroy with data inside

- **WHEN** production is destroyed while the registry holds images, the bucket holds files and the database holds data
- **THEN** the destroy finishes in one run
- **AND** no production resource is left in AWS

#### Scenario: Re-create after a destroy

- **WHEN** production is created again right after a destroy
- **THEN** the apply succeeds with no name collision and no manual cleanup

### Requirement: Bootstrap stays protected

The production Terraform root, `src/infra/envs/production/`, MUST NOT manage the state bucket, the GitHub OIDC provider, or the plan and deploy roles.
It SHALL keep its state in the state bucket, under the key `production/terraform.tfstate`.

#### Scenario: After a destroy

- **WHEN** production is destroyed
- **THEN** the state bucket, the OIDC provider and both roles still exist
- **AND** the bootstrap state is unchanged
