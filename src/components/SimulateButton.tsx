import { useState } from 'react';

interface SimulateModalProps {
  isOpen: boolean;
  onClose: () => void;
}

function SimulateModal({ isOpen, onClose }: SimulateModalProps) {
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
            <li>Generate 4 test wallets</li>
            <li>Fund each wallet with 1 BERA and 100 HONEY</li>
            <li>Have each wallet purchase 1 lottery ticket</li>
          </ul>
        </div>

        <button onClick={onClose} 
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

export function SimulateButton() {
  const [isSimulateOpen, setIsSimulateOpen] = useState(false);

  return (
    <>
      <div className="fixed bottom-4 right-4 group z-40">
        <button 
          onClick={() => setIsSimulateOpen(true)}
          className="text-2xl relative"
        >
          🐻
          <div className="invisible group-hover:visible absolute right-full mr-2 top-1/2 -translate-y-1/2
                        px-3 py-1 bg-black/80 text-amber-200 text-sm rounded-lg whitespace-nowrap">
            Get some bots to participate in the lottery!
          </div>
        </button>
      </div>

      <SimulateModal 
        isOpen={isSimulateOpen} 
        onClose={() => setIsSimulateOpen(false)} 
      />
    </>
  );
} 