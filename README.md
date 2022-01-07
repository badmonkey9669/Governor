# Governor 
This is an implementation of Polkadot's governance model to work in Ethereum protocols

## Structure
The structure of the contracts borrows from Compound Governor Bravo. We use `delegatecall` through a delegator contract and set a new implementation with the proposed changes after an implementation delay.

#### CurrentLaws.sol
Implementation of the current laws of the land.

#### CallDelegator.sol
Delegator contract. Doesn't do much other than `delegatecall` and `setImplementation`.

#### Timelock.sol
Implement a time delay for a referendum. Execute the referendum code after the time delay.

