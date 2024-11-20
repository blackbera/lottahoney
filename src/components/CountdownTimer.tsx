import { useState, useEffect } from 'react';
import { useLotteryState } from '@/hooks/useLotteryState';
import { useLottery } from '@/hooks/useLottery';

export function CountdownTimer() {
  const { isActive, endTime, drawInProgress } = useLotteryState();
  const { startLottery, initiateDraw } = useLottery();
  const [timeLeft, setTimeLeft] = useState({
    days: 0,
    hours: 0,
    minutes: 0,
    seconds: 0
  });
  const [isEnded, setIsEnded] = useState(false);

  useEffect(() => {
    const calculateTimeLeft = () => {
      if (!isActive || !endTime) {
        setTimeLeft({
          days: 0,
          hours: 0,
          minutes: 0,
          seconds: 0
        });
        setIsEnded(false);
        return;
      }

      const now = new Date().getTime();
      const difference = endTime - now;

      if (difference <= 0) {
        setTimeLeft({
          days: 0,
          hours: 0,
          minutes: 0,
          seconds: 0
        });
        setIsEnded(true);
        return;
      }

      setIsEnded(false);
      setTimeLeft({
        days: Math.floor(difference / (1000 * 60 * 60 * 24)),
        hours: Math.floor((difference / (1000 * 60 * 60)) % 24),
        minutes: Math.floor((difference / 1000 / 60) % 60),
        seconds: Math.floor((difference / 1000) % 60)
      });
    };

    calculateTimeLeft();
    const timer = setInterval(calculateTimeLeft, 1000);

    return () => clearInterval(timer);
  }, [isActive, endTime]);

  // Auto-initiate draw when lottery ends
  useEffect(() => {
    if (isEnded && isActive && !drawInProgress) {
      handleInitiateDraw();
    }
  }, [isEnded, isActive, drawInProgress]);

  const handleStartLottery = async () => {
    try {
      await startLottery();
    } catch (error) {
      console.error('Failed to start lottery:', error);
    }
  };

  const handleInitiateDraw = async () => {
    try {
      await initiateDraw();
    } catch (error) {
      console.error('Failed to initiate draw:', error);
    }
  };

  const renderButton = () => {
    if (!isActive && !isEnded) {
      return (
        <button
          onClick={handleStartLottery}
          className="mt-8 px-6 py-3 bg-gradient-to-r from-amber-500 to-yellow-500 rounded-lg font-bold hover:from-amber-600 hover:to-yellow-600 transition-colors"
        >
          Start Lottery!
        </button>
      );
    }

    if (isActive || drawInProgress) {
      return (
        <button
          onClick={handleInitiateDraw}
          disabled={!isEnded || drawInProgress}
          className={`mt-8 px-6 py-3 rounded-lg font-bold transition-colors ${
            isEnded && !drawInProgress
              ? 'bg-gradient-to-r from-amber-500 to-yellow-500 hover:from-amber-600 hover:to-yellow-600'
              : 'bg-gray-600 cursor-not-allowed'
          }`}
        >
          {drawInProgress ? 'Draw in Progress...' : 'Initiate Draw'}
        </button>
      );
    }

    return null;
  };

  return (
    <div className="flex flex-col items-center">
      <h2 className="text-xl font-bold mb-4 bg-gradient-to-r from-amber-200 to-yellow-400 bg-clip-text text-transparent">
        {!isActive ? 'No Active Lottery' : isEnded ? 'Lottery Ended' : 'Current Lottery Ending In'}
      </h2>
      <div className="flex justify-center gap-8 text-white">
        <div className="flex flex-col items-center">
          <div className="text-5xl font-bold bg-black/30 rounded-lg p-4 min-w-[100px]">
            {timeLeft.days.toString().padStart(2, '0')}
          </div>
          <span className="text-sm mt-2">DAYS</span>
        </div>
        <div className="flex flex-col items-center">
          <div className="text-5xl font-bold bg-black/30 rounded-lg p-4 min-w-[100px]">
            {timeLeft.hours.toString().padStart(2, '0')}
          </div>
          <span className="text-sm mt-2">HOURS</span>
        </div>
        <div className="flex flex-col items-center">
          <div className="text-5xl font-bold bg-black/30 rounded-lg p-4 min-w-[100px]">
            {timeLeft.minutes.toString().padStart(2, '0')}
          </div>
          <span className="text-sm mt-2">MINUTES</span>
        </div>
        <div className="flex flex-col items-center">
          <div className="text-5xl font-bold bg-black/30 rounded-lg p-4 min-w-[100px]">
            {timeLeft.seconds.toString().padStart(2, '0')}
          </div>
          <span className="text-sm mt-2">SECONDS</span>
        </div>
      </div>

      {renderButton()}
    </div>
  );
} 