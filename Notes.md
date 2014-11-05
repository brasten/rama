# Notes #
 
A random list of things I want this framework to support.


### The name of the primary id argument in a route should be prefixed with its resource name ###
 
`/customers/:id` should be `/customers/:customer_id`
  
This cleans up the reusable code between a Customers controller handling `/customers/:customer_id`
and an Addresses controller handling `/customers/:customer_id/addresses`.

It even helps cases like `/accounts/:account_id` where the account's owner will often be stored in a field
in the account record called `customer_id`.


### Should be able to add functionality to multiple routes in the router definition itself ###

It should be possible (even preferable?) to declare common functionality in the routes themselves.

Actually the Rack Builder itself is pretty close.