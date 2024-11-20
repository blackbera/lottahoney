import { useState, useEffect } from 'react';
import Image from 'next/image';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { useLottery } from '@/hooks/useLottery';
import { usePurchaseTicket } from '@/hooks/usePurchaseTicket';
import { formatEther, parseEther } from 'viem';
import { useLotteryState } from '@/hooks/useLotteryState';
import { useBGTPrice } from '@/hooks/useBGTPrice';
import { ADDRESSES } from '@/config/addresses';
import LotteryVaultABI from '@/abis/LotteryVaultABI';
import HoneyABI from '@/abis/HoneyABI';


interface EarningsTileProps {
  bgtEarned: string;
  isClaimable: boolean;
  onClaim: () => void;
  isLoading?: boolean;
}

function BGTEarningsTile({ address }: { address?: string }) {
  const lotteryAddress = ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`
  const { isActive } = useLotteryState()
  const { formatUSDValue } = useBGTPrice()
  
  const { data: earnedBGT } = useReadContract({
    address: lotteryAddress,
    abi: LotteryVaultABI,
    functionName: 'earned',
    args: [address as `0x${string}`],
    query: {
      enabled: Boolean(address)
    }
  })

  const { getReward, isLoading } = useLottery()

  const handleClaim = async () => {
    if (!address) return
    await getReward(address, address)
  }

  const formattedBGT = earnedBGT ? formatEther(earnedBGT) : '0'
  const formattedUSD = formatUSDValue(formattedBGT)
  const isClaimable = isActive && earnedBGT ? BigInt(earnedBGT) > BigInt(0) : false

  return (
    <div className="bg-black/30 backdrop-blur-sm rounded-3xl p-6 border border-amber-200/20 hover:border-amber-200/40 transition-all flex flex-col">
      <div className="flex items-center gap-4 mb-6">
        <div className="w-12 h-12 rounded-full bg-amber-200/20 flex items-center justify-center">
          <Image
            src="/bgt.png"
            alt="BGT" 
            width={32}
            height={32}
          />
        </div>
        <div>
          <h3 className="text-xl font-bold text-white">BGT Earnings</h3>
          <p className="text-amber-200">From lottery participation</p>
        </div>
      </div>

      <div className="flex-grow">
        <div className="text-4xl font-bold text-white mb-1">
          {formattedBGT} BGT
        </div>
        <div className="text-lg text-amber-200/80 mb-2">
          {formattedUSD || '$0.00'}
        </div>
        <div className="text-amber-200/60">
          {isActive ? 'Available to claim' : 'Lottery not active'}
        </div>
      </div>

      <button
        onClick={handleClaim}
        disabled={!isClaimable || isLoading}
        className={`w-full py-2 px-4 rounded-lg font-bold transition-all ${
          isClaimable 
            ? 'bg-gradient-to-r from-amber-200 to-yellow-400 text-black hover:opacity-90'
            : 'bg-gray-600 text-gray-400 cursor-not-allowed'
        }`}
      >
        {isLoading ? 'Claiming...' : isClaimable ? 'Claim BGT' : 'Nothing to Claim'}
      </button>
    </div>
  );
}

export function HoneyLotteryTiles() {
  const { address } = useAccount();
  const { isActive } = useLotteryState();
  const {
    totalPool,
    participants,
    approveAndPurchase,
    isApprovePending,
    isPurchasePending,
    isReading,
    error,
  } = useLottery();

  const [ticketCount, setTicketCount] = useState<number>(1);
  const showLoadingState = (isApprovePending || isPurchasePending) && !isReading;

  // Approval transaction
  const { 
    data: approvalHash,
    isPending: isApprovalPending,
    writeContract: writeApprove 
  } = useWriteContract()

  // Purchase transaction
  const {
    data: purchaseHash,
    isPending: isLotteryPurchasePending,
    writeContract: writePurchase
  } = useWriteContract()

  // Watch for transaction confirmations
  const { isLoading: isApprovalConfirming, isSuccess: isApprovalConfirmed } = 
    useWaitForTransactionReceipt({ hash: approvalHash })

  const { isLoading: isPurchaseConfirming, isSuccess: isPurchaseConfirmed } = 
    useWaitForTransactionReceipt({ hash: purchaseHash })

  const [pendingAmount, setPendingAmount] = useState<number | null>(null);

  useEffect(() => {
    if (isApprovalConfirmed && pendingAmount) {
      writePurchase({
        address: ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`,
        abi: LotteryVaultABI,
        functionName: 'purchaseTicket',
        args: [BigInt(pendingAmount)]
      })
      setPendingAmount(null)
    }
  }, [isApprovalConfirmed, pendingAmount, writePurchase])

  const handlePurchase = async (amount: number) => {
    try {
      setPendingAmount(amount)
      await writeApprove({
        address: ADDRESSES.HONEY_ADDRESS as `0x${string}`,
        abi: HoneyABI,
        functionName: 'approve',
        args: [ADDRESSES.LOTTERY_VAULT_ADDRESS, parseEther(amount.toString())]
      })
    } catch (error) {
      console.error('Transaction failed:', error)
      setPendingAmount(null)
    }
  }

  const renderActionButton = () => {
    if (!address) {
      return (
        <p className="text-amber-200/60 text-center">
          Connect wallet to participate
        </p>
      );
    }

    return (
      <>
        <div className="flex items-center gap-2">
          <button 
            onClick={() => setTicketCount(Math.max(1, ticketCount - 1))}
            className="bg-amber-200/20 hover:bg-amber-200/30 text-white px-3 py-1 rounded-lg"
            disabled={showLoadingState || !isActive}
          >
            -
          </button>
          <input
            type="number"
            value={ticketCount}
            onChange={(e) => setTicketCount(Math.max(1, parseInt(e.target.value) || 1))}
            className="bg-amber-200/10 text-white text-center w-20 px-2 py-1 rounded-lg"
            min="1"
            disabled={showLoadingState || !isActive}
          />
          <button
            onClick={() => setTicketCount(ticketCount + 1)}
            className="bg-amber-200/20 hover:bg-amber-200/30 text-white px-3 py-1 rounded-lg"
            disabled={showLoadingState || !isActive}
          >
            +
          </button>
        </div>
        <button
          onClick={() => handlePurchase(ticketCount)}
          disabled={showLoadingState || !isActive}
          className={`w-full font-bold py-2 px-4 rounded-lg transition-all ${
            isActive 
              ? 'bg-gradient-to-r from-amber-200 to-yellow-400 text-black hover:opacity-90 disabled:opacity-50'
              : 'bg-gray-600 text-gray-400 cursor-not-allowed'
          }`}
        >
          {showLoadingState 
            ? isApprovePending 
              ? 'Approving HONEY...'
              : 'Purchasing...'
            : !isActive 
              ? 'Lottery Not Active'
              : 'Purchase Tickets'}
        </button>
      </>
    );
  };

  // Format the pool amount for display
  const formattedPool = totalPool ? formatEther(totalPool) : '0'

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div className="bg-black/30 backdrop-blur-sm rounded-3xl p-6 border border-amber-200/20 hover:border-amber-200/40 transition-all">
        <div className="flex items-center gap-4 mb-6">
          <div className="w-12 h-12 rounded-full bg-amber-200/20 flex items-center justify-center">
            <Image
              src="/honey.png"
              alt="Honey"
              width={32}
              height={32}
            />
          </div>
          <div>
            <h3 className="text-xl font-bold text-white">Honey Lottery</h3>
            <p className="text-amber-200">Win HONEY rewards</p>
          </div>
        </div>

        <div className="mb-6">
          <div className="text-white mb-2">
            <span className="text-amber-200">
              {isActive ? 'Current Prize Pool' : 'Lottery Not Started'}
            </span>
          </div>
          <div className="text-4xl font-bold text-white mb-1">
            {formattedPool} HONEY
          </div>
          <div className="text-amber-200/60">
            Participants: {participants?.length || 0}
          </div>
        </div>

        <div className="space-y-4">
          {renderActionButton()}
          {error && (
            <p className="text-red-500 text-sm">
              {error.message || 'Something went wrong'}
            </p>
          )}
        </div>
      </div>

      <BGTEarningsTile address={address} />
    </div>
  );
} 