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
import { simulateLottery } from '@/hooks/simulateLottery';

interface EarningsTileProps {
  bgtEarned: string;
  isClaimable: boolean;
  onClaim: () => void;
  isLoading?: boolean;
}

const formatBeraValue = (amount: string | number) => {
  const beraPrice = 13; // Hardcoded BERA price in USD
  const value = typeof amount === 'string' ? parseFloat(amount) : amount;
  return `$${(value * beraPrice).toFixed(2)}`;
};

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

interface SimulateModalProps {
  isOpen: boolean;
  onClose: () => void;
}

function SimulateModal({ isOpen, onClose }: SimulateModalProps) {
  const handleSimulate = async () => {
    try {
      await simulateLottery();
      onClose();
    } catch (error) {
      console.error('Simulation failed:', error);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      
      <div className="relative bg-[#1A1B23]/90 backdrop-blur-xl rounded-3xl p-8 w-full max-w-lg mx-4 
                    border border-amber-500/20 shadow-[0_8px_32px_0_rgba(255,198,41,0.25)]">
        <button onClick={onClose} className="absolute top-4 right-4 text-amber-200/60 hover:text-amber-200">
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <h2 className="text-2xl font-bold text-center mb-6 bg-gradient-to-r from-amber-200 to-yellow-400 
                     bg-clip-text text-transparent">
          Simulate Lottery Participants
        </h2>

        <div className="text-amber-200/80 mb-6">
          <p className="mb-4">This will:</p>
          <ul className="list-disc list-inside space-y-2">
            <li>Generates 4 test wallets</li>
            <li>Each wallet will have 1 BERA and 100 HONEY</li>
            <li>Each wallet will purchase 1 lottery ticket</li>
          </ul>
        </div>

        <button onClick={handleSimulate} 
                className="w-full bg-gradient-to-r from-amber-500 to-yellow-500 
                         hover:from-amber-600 hover:to-yellow-600
                         text-white font-bold py-4 px-6 rounded-xl
                         transition-all duration-200">
          Get Some lottery participants in here with you!
        </button>
      </div>
    </div>
  );
}

interface PurchaseModalProps {
  isOpen: boolean;
  onClose: () => void;
  ticketCount: number;
  isApproving: boolean;
  isPurchasing: boolean;
  onApprove: (amount: number) => void;
  onPurchase: (amount: number) => void;
}

function PurchaseModal({ 
  isOpen, 
  onClose, 
  ticketCount,
  isApproving,
  isPurchasing,
  onApprove,
  onPurchase 
}: PurchaseModalProps) {
  if (!isOpen) return null;

  const isProcessing = isApproving || isPurchasing;
  const beraValue = formatBeraValue(ticketCount)
  
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />
      
      <div className="relative bg-[#1A1B23]/90 backdrop-blur-xl rounded-3xl p-8 w-full max-w-lg mx-4 
                    border border-amber-500/20 shadow-[0_8px_32px_0_rgba(255,198,41,0.25)]">
        {!isProcessing && (
          <button 
            onClick={onClose} 
            className="absolute top-4 right-4 text-amber-200/60 hover:text-amber-200"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        )}

        <h2 className="text-2xl font-bold text-center mb-6 bg-gradient-to-r from-amber-200 to-yellow-400 
                     bg-clip-text text-transparent">
          Purchase Lottery Tickets
        </h2>

        <div className="text-amber-200/80 mb-6">
          <p className="mb-4">You are about to:</p>
          <ul className="list-disc list-inside space-y-2">
            <li>Purchase {ticketCount} lottery ticket{ticketCount > 1 ? 's' : ''}</li>
            <li>Cost: {ticketCount} BERA (≈ {beraValue} HONEY)</li>
            <li className="text-sm opacity-80">1 BERA ≈ {formatBeraValue(1)} HONEY</li>
          </ul>
        </div>

        <div className="space-y-4">
          {isApproving ? (
            <div className="text-center text-amber-200">
              <div className="animate-spin inline-block w-6 h-6 border-2 border-current border-t-transparent rounded-full mb-2" />
              <p>Approving HONEY...</p>
            </div>
          ) : isPurchasing ? (
            <div className="text-center text-amber-200">
              <div className="animate-spin inline-block w-6 h-6 border-2 border-current border-t-transparent rounded-full mb-2" />
              <p>Purchasing tickets...</p>
            </div>
          ) : (
            <button
              onClick={() => onApprove(1)}
              className="w-full bg-gradient-to-r from-amber-500 to-yellow-500 
                       hover:from-amber-600 hover:to-yellow-600
                       text-white font-bold py-4 px-6 rounded-xl
                       transition-all duration-200"
            >
              Approve HONEY
            </button>
          )}
        </div>
      </div>
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

  const [isPurchaseModalOpen, setIsPurchaseModalOpen] = useState(false);
  const [pendingAmount, setPendingAmount] = useState<number | null>(null);
  const [isSimulateOpen, setIsSimulateOpen] = useState(false);

  const handleStartPurchase = () => {
    setIsPurchaseModalOpen(true);
  };

  const handleApprove = async (amount: number) => {
    try {
      setPendingAmount(amount);
      await writeApprove({
        address: ADDRESSES.HONEY_ADDRESS as `0x${string}`,
        abi: HoneyABI,
        functionName: 'approve',
        args: [ADDRESSES.LOTTERY_VAULT_ADDRESS, parseEther(amount.toString())]
      });
    } catch (error) {
      console.error('Approval failed:', error);
      setPendingAmount(null);
      setIsPurchaseModalOpen(false);
    }
  };

  const handlePurchase = async (amount: number) => {
    try {
      await writePurchase({
        address: ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`,
        abi: LotteryVaultABI,
        functionName: 'purchaseTicket',
        args: [BigInt(amount)]
      });
    } catch (error) {
      console.error('Purchase failed:', error);
      setPendingAmount(null);
      setIsPurchaseModalOpen(false);
    }
  };

  // Handle transaction flow
  useEffect(() => {
    if (isApprovalConfirmed && pendingAmount) {
      handlePurchase(pendingAmount);
    }
  }, [isApprovalConfirmed, pendingAmount]);

  useEffect(() => {
    if (isPurchaseConfirmed) {
      setPendingAmount(null);
      setIsPurchaseModalOpen(false);
    }
  }, [isPurchaseConfirmed]);

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
            disabled={!isActive}
          >
            -
          </button>
          <input
            type="number"
            value={ticketCount}
            onChange={(e) => setTicketCount(Math.max(1, parseInt(e.target.value) || 1))}
            className="bg-amber-200/10 text-white text-center w-20 px-2 py-1 rounded-lg"
            min="1"
            disabled={!isActive}
          />
          <button
            onClick={() => setTicketCount(ticketCount + 1)}
            className="bg-amber-200/20 hover:bg-amber-200/30 text-white px-3 py-1 rounded-lg"
            disabled={!isActive}
          >
            +
          </button>
        </div>
        <button
          onClick={handleStartPurchase}
          disabled={!isActive}
          className={`w-full font-bold py-2 px-4 rounded-lg transition-all ${
            isActive 
              ? 'bg-gradient-to-r from-amber-200 to-yellow-400 text-black hover:opacity-90'
              : 'bg-gray-600 text-gray-400 cursor-not-allowed'
          }`}
        >
          Buy a Ticket!
        </button>
      </>
    );
  };

  // Format the pool amount for display
  const formattedPool = totalPool ? formatEther(totalPool) : '0'

  const isApproving = isApprovalPending || isApprovalConfirming;
  const isPurchasing = isLotteryPurchasePending || isPurchaseConfirming;

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div className="bg-black/30 backdrop-blur-sm rounded-3xl p-6 border border-amber-200/20 hover:border-amber-200/40 transition-all relative">
        <div className="absolute top-4 right-4 group">
          <button 
            onClick={() => setIsSimulateOpen(true)}
            className="text-2xl relative"
          >
            🐻
            <div className="invisible group-hover:visible absolute bottom-full left-1/2 -translate-x-1/2 mb-2
                          px-3 py-1 bg-black/80 text-amber-200 text-sm rounded-lg whitespace-nowrap">
              Get some bots to participate in the lottery!
            </div>
          </button>
        </div>

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
            {formattedPool} BERA
          </div>
          <div className="text-lg text-amber-200/80 mb-2">
            ≈ {formatBeraValue(formattedPool)} HONEY
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
      
      <SimulateModal 
        isOpen={isSimulateOpen} 
        onClose={() => setIsSimulateOpen(false)} 
      />
      
      <PurchaseModal 
        isOpen={isPurchaseModalOpen}
        onClose={() => !isApproving && !isPurchasing && setIsPurchaseModalOpen(false)}
        ticketCount={ticketCount}
        isApproving={isApproving}
        isPurchasing={isPurchasing}
        onApprove={handleApprove}
        onPurchase={handlePurchase}
      />
    </div>
  );
} 