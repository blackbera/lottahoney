import { useState, useEffect } from 'react';
import { useLotteryState } from '@/hooks/useLotteryState';
import { useLottery } from '@/hooks/useLottery';
import { useWaitForTransactionReceipt } from 'wagmi';

interface StartLotteryModalProps {
  isOpen: boolean;
  onClose: () => void;
  isStarting: boolean;
  onStart: () => void;
  confirmationMessage?: string | null;
}

function StartLotteryModal({
  isOpen,
  onClose,
  isStarting,
  onStart,
  confirmationMessage
}: StartLotteryModalProps) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />
      
      <div className="relative bg-[#1A1B23]/90 backdrop-blur-xl rounded-3xl p-8 w-full max-w-lg mx-4 
                    border border-amber-500/20 shadow-[0_8px_32px_0_rgba(255,198,41,0.25)]">
        {!isStarting && (
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
          Start New Lottery
        </h2>

        <div className="text-amber-200/80 mb-6">
          <p className="mb-4">This will:</p>
          <ul className="list-disc list-inside space-y-2">
            <li>Start a new lottery round</li>
            <li>Set duration to 24 hours</li>
            <li>Allow users to purchase tickets</li>
          </ul>
        </div>

        <div className="space-y-4">
          {isStarting && (
            <div className="text-center text-amber-200">
              <div className="animate-spin inline-block w-6 h-6 border-2 border-current border-t-transparent rounded-full mb-2" />
              <p>{confirmationMessage || "Starting lottery..."}</p>
            </div>
          )}
          <button
            onClick={onStart}
            className="w-full bg-gradient-to-r from-amber-500 to-yellow-500 
                     hover:from-amber-600 hover:to-yellow-600
                     text-white font-bold py-4 px-6 rounded-xl
                     transition-all duration-200"
          >
            Start Lottery
          </button>
        </div>
      </div>
    </div>
  );
}

function DrawModal({ 
  isOpen, 
  onClose, 
  isDrawing,
  winner 
}: { 
  isOpen: boolean;
  onClose: () => void;
  isDrawing: boolean;
  winner: string | null;
}) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />
      
      <div className="relative bg-[#1A1B23]/90 backdrop-blur-xl rounded-3xl p-8 w-full max-w-lg mx-4 
                    border border-amber-500/20 shadow-[0_8px_32px_0_rgba(255,198,41,0.25)]">
        <h2 className="text-2xl font-bold text-center mb-6 bg-gradient-to-r from-amber-200 to-yellow-400 
                     bg-clip-text text-transparent">
          Lottery Draw
        </h2>

        <div className="text-center text-amber-200">
          {isDrawing ? (
            <>
              <div className="animate-spin inline-block w-6 h-6 border-2 border-current border-t-transparent rounded-full mb-2" />
              <p>Drawing winner...</p>
            </>
          ) : winner ? (
            <>
              <p className="mb-4">🎉 Winner Selected! 🎉</p>
              <p className="break-all font-mono bg-black/30 p-4 rounded-lg">
                {winner}
              </p>
            </>
          ) : null}
        </div>

        {!isDrawing && winner && (
          <button
            onClick={onClose}
            className="w-full mt-6 bg-gradient-to-r from-amber-500 to-yellow-500 
                     hover:from-amber-600 hover:to-yellow-600
                     text-white font-bold py-4 px-6 rounded-xl
                     transition-all duration-200"
          >
            Close
          </button>
        )}
      </div>
    </div>
  );
}

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
  const [isStartLotteryModalOpen, setIsStartLotteryModalOpen] = useState(false);
  const [isStarting, setIsStarting] = useState(false);
  const [isDrawModalOpen, setIsDrawModalOpen] = useState(false);
  const [isDrawing, setIsDrawing] = useState(false);
  const [winner, setWinner] = useState<string | null>(null);

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
      setIsStarting(true);
      await startLottery();
      window.location.reload();  // Reload immediately after success
    } catch (error) {
      console.error('Failed to start lottery:', error);
      setIsStarting(false);
      setIsStartLotteryModalOpen(false);
    }
  };

  const handleInitiateDraw = async () => {
    try {
      setIsDrawing(true);
      setIsDrawModalOpen(true);
      await initiateDraw();
      // Winner will be set via event listener
    } catch (error) {
      console.error('Failed to initiate draw:', error);
      setIsDrawing(false);
      setIsDrawModalOpen(false);
    }
  };

  const renderButton = () => {
    if (!isActive && !isEnded) {
      return (
        <button
          onClick={() => setIsStartLotteryModalOpen(true)}
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
      
      <StartLotteryModal 
        isOpen={isStartLotteryModalOpen}
        onClose={() => !isStarting && setIsStartLotteryModalOpen(false)}
        isStarting={isStarting}
        onStart={handleStartLottery}
        confirmationMessage={isStarting ? "Starting lottery..." : null}
      />
      
      <DrawModal 
        isOpen={isDrawModalOpen}
        onClose={() => {
          setIsDrawModalOpen(false);
          setWinner(null);
          window.location.reload();
        }}
        isDrawing={isDrawing}
        winner={winner}
      />
    </div>
  );
} 