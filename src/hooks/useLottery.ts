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
  import { useEffect } from 'react'
  
  export function useLottery() {
    const { address } = useAccount()
    const lotteryAddress = ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`
    const honeyAddress = ADDRESSES.HONEY_ADDRESS as `0x${string}`
  
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
        staleTime: 1_000,     
        refetchInterval: 1_000,
        retry: 2,
        retryDelay: 1000
      }
    })
  
    // Destructure with default values to prevent undefined states
    const [
      isActive = false,
      totalPool = BigInt(0),
      timeRemaining = BigInt(0),
      participants = []
    ] = (lotteryData?.map(result => {
      return 'result' in result ? result.result : result
    }) || []) as [boolean, bigint, bigint, string[]]
  
  
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
  
    useEffect(() => {
      if (isConfirmed && hash) {
        console.log('Transaction confirmed with hash:', hash)
      }
    }, [isConfirmed, hash])
  
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
      if (!address) {
        console.log('No wallet address found');
        return;
      }
      
      try {
        console.log('=== Starting Lottery Flow ===')
        console.log('User address:', address)
        console.log('Lottery address:', lotteryAddress)
        
        const result = await writeContract({
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'startLottery',
        });
        console.log('Start lottery transaction hash:', result);

        await refetch();
        console.log('State refetched after lottery start')
        console.log('=== Lottery Start Flow Complete ===')
        return result;
      } catch (error) {
        console.error('=== Error Starting Lottery ===')
        console.error('Error details:', error)
        console.error('=== End Error Log ===')
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
  
    const { writeContract: writeApprove, isPending: isApprovePending } = useWriteContract()
    const { writeContract: writePurchase, isPending: isPurchasePending } = useWriteContract()
  
    const approveAndPurchase = async (amount: number) => {
      if (!address) return
  
      try {
        console.log('=== Starting Approve & Purchase Flow ===')
        console.log('User address:', address)
        console.log('Lottery address:', lotteryAddress)
        console.log('HONEY token address:', honeyAddress)
        console.log('Amount to approve/purchase:', amount)

        // First approve
        console.log('Initiating HONEY approval...')
        const approveAmount = parseEther(amount.toString())
        console.log('Approval amount (in wei):', approveAmount)
        
        const approveTx = await writeApprove({
          address: honeyAddress,
          abi: ERC20ABI,
          functionName: 'approve',
          args: [lotteryAddress, approveAmount]
        })
        console.log('Approval transaction submitted:', approveTx)

        // Then purchase
        console.log('Initiating ticket purchase...')
        const purchaseTx = await writePurchase({
          address: lotteryAddress,
          abi: LotteryVaultABI,
          functionName: 'purchaseTicket',
          args: [BigInt(amount)]
        })
        console.log('Purchase transaction submitted:', purchaseTx)

        await refetch()
        console.log('State refetched after transactions')
        console.log('=== Approve & Purchase Flow Complete ===')

      } catch (error) {
        console.error('=== Error in Approve & Purchase Flow ===')
        console.error('Error details:', error)
        if (error instanceof Error) {
          console.error('Error message:', error.message)
        }
        console.error('=== End Error Log ===')
        throw error
      }
    }
  
    // Modify the isLoading combination
    const isLoading = isWritePending || isConfirming || isRewardPending || isApprovePending || isPurchasePending
  
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
      approveAndPurchase,
      
      // Status
      isLoading,
      isReading,
      error,
      isSuccess: isConfirmed,
      isRewardPending,
      isApprovePending,
      isPurchasePending
    }
  } 