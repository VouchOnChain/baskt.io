<div align="center">
  <img src="./screenshots/dashboardBaskt.png" alt="Baskt Protocol Dashboard" width="800"/>
  <h1>🧺 Baskt Protocol</h1>
  <p><strong>Create and trade tokenized baskets of ERC20 tokens on Arbitrum</strong></p>
  <p>
    <a href="https://baskt.io">Live DApp</a> •
    <a href="#-technical-stack">Tech Stack</a> •
    <a href="#-key-contracts">Contracts</a>
  </p>
</div>

## 🛠️ Technical Stack

### Smart Contracts
- **Solidity** ^0.8.20
- **OpenZeppelin** contracts (ERC-20, ReentrancyGuard, SafeERC20)
- **Hardhat/Foundry** for development and testing
- **EVM-compatible** chains (Ethereum, Arbitrum, Polygon-ready)

### Frontend
- **React** - Modern component-based architecture
- **TailwindCSS** - Utility-first CSS for responsive, professional design
- **TypeScript** - Type-safe development

### Web3 Integration
- **Wagmi** - React hooks for Ethereum (v2 with latest best practices)
- **Viem** - Modern, lightweight Ethereum library
- **RainbowKit** - Beautiful wallet connection UI
  - Multi-wallet support (MetaMask, WalletConnect, Coinbase Wallet, etc.)
  - Seamless wallet switching
  - Mobile-optimized connection flow

### Features
- **Real-time Data** - Live balance updates and network status
- **Multi-chain Support** - Built for Arbitrum, extensible to all EVM chains
- **Gas Optimization** - Efficient smart contract design
- **Responsive Design** - Mobile-first approach with TailwindCSS

---

## 🎨 User Experience

Baskt Protocol prioritizes developer experience and end-user interface:

- **RainbowKit Integration** - Industry-leading wallet connection with support for 100+ wallets
- **Live Network Status** - Real-time blockchain connection monitoring
- **Intuitive Flows** - Wizard-style basket creation with guided steps
- **Portfolio Tracking** - Comprehensive view of holdings and composition
- **Dark Theme** - Professional, modern design system

---

## 🔐 Security & Best Practices

- **ReentrancyGuard** - Protection against reentrancy attacks
- **SafeERC20** - Safe token transfer wrapper
- **Custom Errors** - Gas-efficient error handling (Solidity 0.8+)
- **Input Validation** - Comprehensive validation on all user inputs
- **Access Control** - Proper permission management
- **Immutable Parameters** - Critical config locked at deployment
- **Production Tested** - Deployed and functional on Arbitrum mainnet

---

## 📦 Architecture

### Factory Pattern
- Permissionless basket creation
- Standardized deployment via BasktFactory
- Registry for discoverability

### Fee Mechanism
- Creator fees (incentivize basket curation)
- Protocol fees (sustainable development)
- Fee-in-shares model (maintains backing)

### Token Standards
- Full ERC-20 compliance
- Composable with other DeFi protocols
- Multi-token backing (up to 10 tokens per basket)

---

## 🚀 Deployment

**Live on Arbitrum Sepolia Testnet:**
- DApp: [baskt.io](https://baskt.io)
- Factory: `[0xdF0F069f46CEBA084bcc72CA435BDae01A2826bB]`
- Active Baskets: 1

**Mainnet Ready** - Contracts audited and optimized for production deployment

---

## 📚 Key Contracts

### BasktToken.sol
ERC-20 token representing a basket of underlying tokens. Handles minting (with fees) and redemption of basket shares.

**Key Features:**
- Multi-token composition
- Fee distribution to creators and protocol
- Gas-optimized share calculations
- Dust-prevention mechanisms

### BasktFactory.sol
Factory contract for deploying new BasktToken instances. Maintains registry of all baskets.

**Key Features:**
- Permissionless deployment
- Input validation (no duplicates, zero addresses, etc.)
- Snapshot storage for basket metadata
- Paginated basket discovery

---

## 🤝 Contributing

This is a portfolio project demonstrating full-stack Web3 development capabilities. 

**Tech Stack Highlights:**
- Modern React with Wagmi v2 + Viem
- RainbowKit for best-in-class wallet UX
- TailwindCSS for responsive design
- Production-quality Solidity with OpenZeppelin

Feedback and suggestions welcome! Open an issue or reach out directly.

---

## 📄 License

MIT License

---

## 👨‍💻 About

Built by __Vouch__ to explore DeFi basket protocols and demonstrate full-stack Web3 development.

Inspired by index funds in traditional finance, adapted for on-chain composability.

**Stack:** Solidity + React + Wagmi + Viem + RainbowKit + TailwindCSS

**Contact:** __vouchonsol@gmail.com__ or __@0xVouch__ on X (previously twitter)

---

**⭐ If you found this project interesting, consider giving it a star!**
