
# Troubleshooting

## "unable to pin image company/hello-world:8f1fd4a4ee47 to digest: manifest unknown: manifest unknown", or "denied: requested access to the resource is denied", or "unauthorized: authentication required"

Harmless, given the image was uploaded earlier to the Swarm (image:push). This message means the image could not be found on the public Docker Registry.

## The wrong version of my project is deployed

Check that you've built and deployed the project using the same TAG. Using 'latest' can lead to inconsistency.
