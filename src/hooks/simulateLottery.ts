import { 
  createWalletClient, 
  http, 
  parseEther,
  Account,
  WalletClient,
  formatEther
} from 'viem'

import { generatePrivateKey, privateKeyToAccount  } from 'viem/accounts'
import { berachainTestnetbArtio } from 'viem/chains'
import HoneyABI from '../abis/HoneyABI'
import LotteryVaultABI from '../abis/LotteryVaultABI'
import { ADDRESSES } from '../config/addresses'
import { config } from 'dotenv'

config()

const NUM_WALLETS = 4
const BERA_PER_WALLET = '1' // in BERA
const HONEY_PER_WALLET = '100' // in HONEY
const TICKETS_PER_WALLET = 1

interface TestWallet {
  account: Account
  address: string
  privateKey: string
}

async function generateWallets(count: number): Promise<TestWallet[]> {
  return Array.from({ length: count }, () => {
    const privateKey = generatePrivateKey()
    const account = privateKeyToAccount(privateKey)
    return {
      account,
      address: account.address,
      privateKey
    }
  })
}

async function setupClient(): Promise<WalletClient> {
  return createWalletClient({
    chain: berachainTestnetbArtio,
    transport: http()
  })
}

async function fundWallet(
  client: WalletClient, 
  adminAccount: Account,
  wallet: TestWallet
) {
  console.log(`\nFunding wallet: ${wallet.address}`)
  
  // Send BERA
  const beraTx = await client.sendTransaction({
    account: adminAccount,
    to: wallet.address as `0x${string}`,
    value: parseEther(BERA_PER_WALLET),
    chain: berachainTestnetbArtio
  })
  console.log(`Sent ${BERA_PER_WALLET} BERA. TX: ${beraTx}`)

  // Send HONEY
  const oneBeraInWei = parseEther("1")

  const transferConfig = {
    account: adminAccount,
    address: ADDRESSES.HONEY_ADDRESS,
    abi: HoneyABI,
    functionName: 'transfer',
    args: [wallet.address, oneBeraInWei],
    chain: berachainTestnetbArtio
  }

  const honeyTx = await client.writeContract(transferConfig)
  console.log(`Sent ${HONEY_PER_WALLET} HONEY. TX: ${honeyTx}`)
}

async function enterLottery(
  client: WalletClient,
  wallet: TestWallet
) {
  console.log(`\nEntering lottery with wallet: ${wallet.address}`)

  // Approve HONEY for lottery
  const approveTx = await client.writeContract({
    account: wallet.account as Account,
    address: ADDRESSES.HONEY_ADDRESS as `0x${string}`,
    abi: HoneyABI,
    functionName: 'approve',
    args: [ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`, parseEther(HONEY_PER_WALLET)],
    chain: berachainTestnetbArtio
  })
  console.log(`Approved HONEY. TX: ${approveTx}`)

  // Purchase tickets
  const purchaseTx = await client.writeContract({
    account: wallet.account as Account,
    address: ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`,
    abi: LotteryVaultABI,
    functionName: 'purchaseTicket',
    args: [BigInt(TICKETS_PER_WALLET)],
    chain: berachainTestnetbArtio
  })
  console.log(`Purchased ${TICKETS_PER_WALLET} ticket(s). TX: ${purchaseTx}`)
}

export const simulateLottery = async () => {
  try {
    // Setup
    const adminAccount = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`)
    console.log(`Admin account: ${adminAccount.address}`)
    const client = await setupClient()
    
    // Generate wallets
    console.log('\nGenerating test wallets...')
    const wallets = await generateWallets(NUM_WALLETS)
    wallets.forEach((wallet, i) => {
      console.log(`\nWallet ${i + 1}:`)
      console.log(`Address: ${wallet.address}`)
      console.log(`Private Key: ${wallet.privateKey}`)
    })

    // Fund and enter lottery with each wallet
    for (const wallet of wallets) {
      await fundWallet(client, adminAccount, wallet)
      await enterLottery(client, wallet)
    }

    console.log('\nSimulation complete! 🎉')
  } catch (error) {
    console.error('Error during simulation:', error)
    throw error
  }
} 