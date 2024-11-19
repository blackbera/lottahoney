import { ConnectButton } from '@rainbow-me/rainbowkit';
import type { NextPage } from 'next';
import Head from 'next/head';
import { LotteryTile } from '../components/LotteryTile';
import Image from 'next/image';
import { CountdownTimer } from '../components/CountdownTimer';

const LOTTERY_CONTRACTS = [
  {
    name: "BEND",
    symbol: "przBEND",
    address: "0x1339503343be5626B40Ee3Aee12a4DF50Aa4C0B9",
    grandPrize: "2,377",
    bgtAmount: "2,377"
  },
  {
    name: "BERPS", 
    symbol: "przBERPS",
    address: "0x1306D3c36eC7E38dd2c128fBe3097C2C2449af64",
    grandPrize: "17,855",
    bgtAmount: "17,855"
  },
  {
    name: "BERA BORROW",
    symbol: "przBERAB",
    address: "0x3a7f6f2F27f7794a7820a32313F4a68e36580864",
    grandPrize: "37,424",
    bgtAmount: "37,424"
  },
  {
    name: "HONEY-WBERA",
    symbol: "przHWBERA",
    address: "0xd28d852cbcc68DCEC922f6d5C7a8185dBaa104B7",
    grandPrize: "1,479",
    bgtAmount: "1,479"
  },
  {
    name: "HONEY-USDC",
    symbol: "przHUSDC",
    address: "0xb73deE52F38539bA854979eab6342A60dD4C8c03",
    grandPrize: "1,565",
    bgtAmount: "1,565"
  },
  {
    name: "YEET KODIAK",
    symbol: "przYEETK",
    address: "0xE5A2ab5D2fb268E5fF43A5564e44c3309609aFF9",
    grandPrize: "161",
    bgtAmount: "161"
  }
];

export default function Home() {
  return (
    <div className="min-h-screen bg-[#1A1B23] bg-[url('/homepage.png')] bg-cover bg-center bg-fixed">
      <div className="min-h-screen bg-black/50 backdrop-blur-sm">
        <div className="absolute top-6 right-6">
          <ConnectButton />
        </div>

        <main className="max-w-7xl mx-auto px-6 py-20">
          <div className="text-center mb-20">
            <div className="flex items-center justify-center gap-6 mb-6">
              <Image
                src="/bgt.png"
                alt="BGT Logo"
                width={100}
                height={100}
                className="w-24 h-24"
              />
              <h1 className="text-6xl font-bold">
                <span className="bg-gradient-to-r from-amber-200 to-yellow-400 bg-clip-text text-transparent">
                  BGT Together
                </span>
              </h1>
            </div>
            
            <p className="text-xl mb-8 font-bold">
              <span className="text-white">Deposit your staking tokens in these lottery vaults</span>
              {' '}
              <span className="bg-gradient-to-r from-amber-200 to-yellow-400 bg-clip-text text-transparent">
                with a chance to win the vaults BGT rewards of that week
              </span>
            </p>

            <CountdownTimer />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {LOTTERY_CONTRACTS.map((lottery) => (
              <LotteryTile 
                key={lottery.address}
                {...lottery}
              />
            ))}
          </div>
        </main>
      </div>
    </div>
  );
}
