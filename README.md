
# Introduction
Riftlend is a lending and borrowing protocol built on super-chain . It means users can 
hassle-freely lend and borrow across all the L2 chains OP superchain supports.

We are a fork of AAVE v2 with major changes in the code that's why you'll see a lot of stuff is similar to how aave v2 works 
with considerable changes to support super-chain paradigm instead of siloed versions of aave v2 on each chain.

Our driving force is to abstract away the details of underlying chains from users and give them an experience closest to whay they see on CEXs.
Our approach , among other things , ensures that interest rates remain uniform across all the chains for a seemless experience .

## How it works ( Level 1 : A high level guide )

You might be wondering how RiftLend works ?
let's see it .

So in order to understand things , assuming you don't know much about aave v2 , we'll start with basics 
and build up from there.

Here are some key points to note to understand the system .

- A Market in Riftlend is an instance of LendingPool designated for each asset . 
i.e USDC and UNI tokens will each have different market in Riftlend .

- Each Market/LendingPool is behind a proxy . The users interact with LendingPool's proxy and those calls are forwarded to the implementation of LendingPool.

- Each LendingPool has a lot of addresses to manage ( store , update and retrieve from ) , the `LendingPoolAddressesProvider` acts as ` Main registry of addresses part of or connected to the protocol, including permissioned roles. Acting also as factory of proxies and admin of those, so with right to change its implementations`

- In future , we will have protocol governance and Protocol Governance owns `LendingPoolAddressesProvider` which owns proxies of LendingPools

- As stated earlier `LendingPoolAddressesProvider` points to only one market ( Only one lendingPool) 

- Users interact with LendingPool because as beautifully stated in the Code Natspec :

```
Main point of interaction with an Aave protocol's market
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Swap their loans between variable and stable rate
 *   # Enable/disable their deposits as collateral rebalance stable rate borrow positions
 *   # Liquidate positions
 *   # Execute Flash Loans
 * - To be covered by a proxy contract, owned by the LendingPoolAddressesProvider of the specific market
 * - All admin functions are callable by the LendingPoolConfigurator contract defined also in the
 *   LendingPoolAddressesProvider
```

So this was a good starter to build rapport of how things work on a high level.


It's time to go a bit deeper to make you a RiftLend wizard.

Since our main point of interaction is `LendingPool` for each asset, Let's dive into it.

## How it works ? ( Level 2 : A relatively deeper analysis )

### LendingPool
#### General 
![Riftlend flow](https://github.com/user-attachments/assets/83b0251a-6685-46be-b11f-952e3aa74d64)

#### When a user performs a state changing action

The state changing actions `ActionX` can be anything listed above like Lend, Borrow , Withdraw etc.

![ActionX flow Riftlend](https://github.com/user-attachments/assets/9d0f567d-8037-411c-a8bb-fb053001aaa9)

Here are the steps involved in the process :

**1. ActionX Initiated:**

   - The user interacts with the Riftlend protocol to perform a state-changing action (e.g., lending, borrowing, repaying, withdrawing, etc.).

**2. Check for Cross-Chain Requirement:**

   - The protocol determines if the ActionX needs to be executed on the current chain or a different chain within the superchain.

**3. Perform ActionX on Current Chain:**

   - If the ActionX can be executed on the current chain, the protocol performs the action directly.
   - An ActionX event is emitted to record the transaction.

**4. Emit CrossChainX Event:**

   - If the ActionX needs to be executed on a different chain, a CrossChainX event is emitted. This event contains information about the action to be performed, the target chain, and any relevant parameters.

**5. Relayer Reads CrossChainX Event:**

   - A relayer, a specialized node in the superchain network, reads the CrossChainX event.

**6. Prepare Cross-Chain Message:**

   - The relayer prepares a cross-chain message containing the necessary information to execute the ActionX on the target chain.

**7. Dispatch Cross-Chain Message:**

   - The relayer dispatches the cross-chain message to the target chain.

**8. Process ActionX on Target Chain:**

   - The target chain receives the cross-chain message and processes the ActionX using `dispatch()` method in LendingPool.
   - The dispatch method decides which action needs to be done for which the event data has been submitted to it.
   - It prepares the action based on exracted params of the event data and peform the action on current chain

All of the functions work the same way .

## How it works ? ( Level 3 : Code exploration )
Coming soon ...

## aTokens , SuperChain Asset and Underlying

Inside Aave V2, whenever we supply or lend some  asset i.e USDC , that asset is called `Underlying`.
For the supplied `underlying` asset , `aTokens` are minted to the `lender` for their supply. 
ATokens follow the naming convention `a` followed by name of the asset like `aUSDC` for `USDC` and `aSTK` for `STK` etc.


But inside Riftlend , across the whole superchain , we have a new paradigm called `SuperChainAsset` that is introduced to 
bring seamless experience to all the super chain users. 

A SuperChainAsset is a `wrapper on underlying asset` that acts as a super form of an asset like superUSDC for USDC and then this superUSDC will act as underlying for aTokens

This can be visualized in following fashion



![aTokens](https://github.com/user-attachments/assets/f931a3c5-656e-4d94-8ac3-93a4933e1059)



## Withdraw & Bridge

Initially , the lending pools will be bootstrapped like in usual defi protocols but when RiftLend gets traction ,
it will gain huge liquidity among different lending pools on different chains. In that setting , we don't rely 
on `burning on source chain and minting on destination chain` like bridge pattern.

With the introduction of `SuperchainAsset` , instead of moving the `underlying asset` i.e USDC when bridging between two differnt chains , we just move the SuperchainAsset equivelant of that asset to destination chain and have the underlying asset on source chain for now with an optional function to initiate the underlying asset's transfer from source chain to destination chain.

This might be confusing .

Let's understand with an example.
Let's say Lender1 lends `100 USDC` to Lending pool on Chain `C1` and they get `100 superUSDC`.
Now they want to `withdraw` their `100 USDC` on chain `C2`. Now Riftlend approach can differ in two scenarios.

1. If Chain C2 has enough liquidity for USDC , then the Lender1 can freely withdraw the assets on chain C2 by converting 
`superUSDC` to `USDC` on chain C2 itself `without` the need to `actually brige the underlying USDC from Chain C1 to C2`. 

2. If Chain C2 does not have enough liquidity , the `underlying asset USDC` from Chain `C1` needs to be `transferred to C2` using a bridge functionality and then Lender1 can withdraw their USDC on Chain C2.

( More information on the way .... )




WIP: 🔨

## 🤝 Contributing

Contributions are encouraged, but please open an issue before making any major changes to ensure your changes will be accepted. Checkout our [Projects board](https://github.com/RiftLend/monorepo-v1/projects?query=is%3Aopen) to see what we are actively planning to work on. We also have a [Telegram Working Group](https://t.me/+sybc0z6anTgzMjc1) to have open discussions.

### 📢 Marketing Support Needed

We're gearing up for our alpha launch and looking for marketing-savvy contributors! If you have experience in:
- DeFi/Web3 content creation
- Community building
- Social media management
- Growth hacking
- Technical writing

Please join our [Telegram Working Group](https://t.me/+sybc0z6anTgzMjc1) or open an issue to discuss how you can help shape RiftLend's market presence. Let's build something amazing together! 🚀

### 🔒 Security Contributors Needed

We're looking for security-minded contributors to help strengthen our protocol! If you have experience or interest in:
- Smart contract security
- Code review and testing
- Security documentation
- Threat modeling
- Best practices implementation

Whether you're a security enthusiast or experienced researcher, we welcome your contributions to make RiftLend more secure. Join our [Telegram Working Group](https://t.me/+sybc0z6anTgzMjc1) or open an issue to discuss how you can help. Let's build a safer DeFi ecosystem together! 🛡️

