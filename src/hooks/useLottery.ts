import { 
    useReadContract,
    useReadContracts,
    useWriteContract,
    useWaitForTransactionReceipt,
    useAccount 
  } from 'wagmi'
  import { ADDRESSES } from '@/config/addresses'
  import LotteryVaultABI from '@/abis/LotteryVaultABI'
  import ERC20ABI from '@/abis/ERC20ABI'
  import { parseEther } from 'viem'
  import RewardVaultABI from '@/abis/RewardVaultABI'
  
  export function useLottery() {
    const { address } = useAccount()
    const lotteryAddress = ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`
  
    // Read multiple lottery states at once with better error handling
    const { 
      data: lotteryData,
      error: readError,
      isPending: isReading,
      refetch 
    } = useReadContracts({
      contracts: [
        {
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'lotteryActive',
        },
        {
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'totalPool',
        },
        {
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'getTimeRemaining',
        },
        {
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'getCurrentParticipants',
        }
      ],
      query: {
        // Add staleTime and refetchInterval for better data management
        staleTime: 5_000, // Consider data fresh for 5 seconds
        refetchInterval: 10_000, // Refetch every 10 seconds
        retry: 2, // Retry failed requests twice
        retryDelay: 1500 // Wait 1.5 seconds between retries
      }
    })
  
    // Destructure with default values to prevent undefined states
    const [
      isActive = false,
      totalPool = BigInt(0),
      timeRemaining = BigInt(0),
      participants = []
    ] = (lotteryData?.map(result => 
      // Extract the result value if it's a success object
      'result' in result ? result.result : result
    ) || []) as [boolean, bigint, bigint, string[]]
  
    // Purchase transaction handling
    const { 
      writeContract,
      data: hash,
      isPending: isWritePending,
      error: writeError
    } = useWriteContract()
  
    // Transaction receipt handling with proper configuration
    const { 
      isLoading: isConfirming,
      isSuccess: isConfirmed,
      error: receiptError
    } = useWaitForTransactionReceipt({
      hash,
      confirmations: 1,
      pollingInterval: 1_000,
      timeout: 30_000
    })
  
    const buyTickets = async (amount: number) => {
      if (!address) return;
      
      try {
        const data = await writeContract({
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'purchaseTicket',
          args: [BigInt(amount)],
        });
        
        await refetch();
        return data;
      } catch (error) {
        console.error('Error buying tickets:', error);
        throw error;
      }
    };
  
    const startLottery = async () => {
      if (!address) return;
      
      try {
        const data = await writeContract({
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'startLottery',
        });
  
        await refetch();
        return data;
      } catch (error) {
        console.error('Error starting lottery:', error);
        throw error;
      }
    };
  
    const initiateDraw = async () => {
      if (!address) return;
      
      try {
        const data = await writeContract({
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'initiateDraw',
        });
        
        await refetch();
        return data;
      } catch (error) {
        console.error('Error initiating draw:', error);
        throw error;
      }
    };
  
    const { writeContract: writeRewardVault, isPending: isRewardPending } = useWriteContract()
  
    const getReward = async (account: string, recipient: string) => {
      if (!account || !recipient) return
      
      return writeRewardVault({
        address: ADDRESSES.REWARDS_VAULT_ADDRESS as `0x${string}`,
        abi: RewardVaultABI,
        functionName: 'getReward',
        args: [account, recipient]
      })
    }
  
    // Modify the isLoading combination
    const isLoading = isWritePending || isConfirming || isRewardPending
  
    // Combine all errors
    const error = readError || writeError || receiptError
  
    return {
      // State
      isActive,
      totalPool,
      timeRemaining,
      participants,
      
      // Actions
      buyTickets,
      refetch,
      startLottery,
      initiateDraw,
      getReward,
      
      // Status
      isLoading,
      isReading,
      error,
      isSuccess: isConfirmed,
      isRewardPending
    }
  } 