import { useReadContract } from 'wagmi';
import LotteryVaultABI from '@/abis/LotteryVaultABI'
import { ADDRESSES } from '@/config/addresses';

export function useLotteryState() {
  const lotteryAddress = ADDRESSES.LOTTERY_VAULT_ADDRESS as `0x${string}`;
  const { data: isActive } = useReadContract({
    address: lotteryAddress,
    abi: LotteryVaultABI,
    functionName: 'lotteryActive',
  });

  const { data: endTime } = useReadContract({
    address: lotteryAddress,
    abi: LotteryVaultABI,
    functionName: 'lotteryEndTime',
  });

  const { data: drawInProgress } = useReadContract({
    address: lotteryAddress,
    abi: LotteryVaultABI,
    functionName: 'drawInProgress',
  });

  return {
    isActive: Boolean(isActive),
    endTime: endTime ? Number(endTime) * 1000 
      : undefined,
    drawInProgress: Boolean(drawInProgress)
  };
} 