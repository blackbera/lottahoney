// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IOrders } from "../interfaces/v0/IOrders.sol";
import { ISettlement } from "../interfaces/v0/ISettlement.sol";

import { BerpsErrors } from "./BerpsErrors.sol";
import { Utils } from "../../libraries/Utils.sol";

library TradeUtils {
    using Utils for bytes4;

    /// @notice used for both open limit orders and open trades
    function _getTradeLastUpdated(
        address _settlement,
        uint256 index
    )
        internal
        view
        returns (ISettlement, ISettlement.LastUpdated memory)
    {
        ISettlement settlement = ISettlement(_settlement);
        ISettlement.LastUpdated memory l = settlement.tradeLastUpdated(index);

        return (settlement, l);
    }

    function setSlLastUpdated(address _settlement, uint256 tradeIndex) internal {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, tradeIndex);

        l.sl = uint64(block.number);
        settlement.setTradeLastUpdated(tradeIndex, l);
    }

    function setTpLastUpdated(address _settlement, uint256 tradeIndex) internal {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, tradeIndex);

        l.tp = uint64(block.number);
        settlement.setTradeLastUpdated(tradeIndex, l);
    }

    function setLimitLastUpdated(address _settlement, uint256 limitIndex) internal {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, limitIndex);

        l.limit = uint64(block.number);
        settlement.setTradeLastUpdated(limitIndex, l);
    }

    function isCloseInTimeout(address _settlement, uint256 tradeIndex) internal view returns (bool) {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, tradeIndex);

        return uint64(block.number) < l.created + settlement.canExecuteTimeout();
    }

    function isTpInTimeout(address _settlement, uint256 tradeIndex) internal view returns (bool) {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, tradeIndex);

        return uint64(block.number) < l.tp + settlement.canExecuteTimeout();
    }

    function isSlInTimeout(address _settlement, uint256 tradeIndex) internal view returns (bool) {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, tradeIndex);

        return uint64(block.number) < l.sl + settlement.canExecuteTimeout();
    }

    function isLimitInTimeout(address _settlement, uint256 limitIndex) internal view returns (bool) {
        (ISettlement settlement, ISettlement.LastUpdated memory l) = _getTradeLastUpdated(_settlement, limitIndex);

        return uint64(block.number) < l.limit + settlement.canExecuteTimeout();
    }

    function revertFor(ISettlement.CancelReason cr) internal pure {
        if (cr == ISettlement.CancelReason.NOT_HIT) {
            BerpsErrors.PriceNotHit.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.SLIPPAGE) {
            BerpsErrors.SlippageExceeded.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.NO_TRADE) {
            BerpsErrors.NoTrade.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.PAUSED) {
            BerpsErrors.Paused.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.TP_REACHED) {
            BerpsErrors.TpReached.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.SL_REACHED) {
            BerpsErrors.SlReached.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.EXPOSURE_LIMITS) {
            BerpsErrors.PastExposureLimits.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.PRICE_IMPACT) {
            BerpsErrors.PriceImpactTooHigh.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.MAX_LEVERAGE) {
            BerpsErrors.LeverageIncorrect.selector.revertWith();
        } else if (cr == ISettlement.CancelReason.IN_TIMEOUT) {
            BerpsErrors.InTimeout.selector.revertWith();
        }
    }
}
