# mvp-ethereum
MVP smart contracts on Ethereum

The set of smart contracts that makes up the core part of Flyion.

Escrow holds the capital (in any token denomination).
Flyion_Chainlink is the interface to the oracle service that ultimately triggers the indemnification of a policy (or the closing of one when no action is necessary).
MSC contains the main business logic, functions to create and subscribe to policies, information about subscribers and policies.
