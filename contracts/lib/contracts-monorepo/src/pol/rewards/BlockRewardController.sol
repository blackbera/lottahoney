// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBlockRewardController } from "../interfaces/IBlockRewardController.sol";
import { IBeaconDeposit } from "../interfaces/IBeaconDeposit.sol";
import { BGT } from "../BGT.sol";

/// @title BlockRewardController
/// @author Berachain Team
/// @notice The BlockRewardController contract is responsible for managing the reward rate of BGT.
/// @dev It should be owned by the governance module.
/// @dev It should also be the only contract that can mint the BGT token.
/// @dev The invariants that should hold true are:
///      - processRewards() is called every block().
///      - processRewards() is only called once per block.
contract BlockRewardController is IBlockRewardController, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The BGT token contract that we are minting to the distributor.
    BGT public bgt;

    /// @notice The Beacon deposit contract to check the pubkey -> operator relationship.
    IBeaconDeposit public beaconDepositContract;

    /// @notice The distributor contract that receives the minted BGT.
    address public distributor;

    /// @notice The constant base rate for BGT.
    uint256 public baseRate;

    /// @notice The reward rate for BGT.
    uint256 public rewardRate;

    /// @notice The minimum reward rate for BGT after accounting for validator boosts.
    uint256 public minBoostedRewardRate;

    /// @notice The boost mutliplier param in the function, determines the inflation cap, 18 dec.
    uint256 public boostMultiplier;

    /// @notice The reward convexity param in the function, determines how fast it converges to its max, 18 dec.
    int256 public rewardConvexity;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bgt,
        address _distributor,
        address _beaconDepositContract,
        address _governance
    )
        external
        initializer
    {
        __Ownable_init(_governance);
        bgt = BGT(_bgt);
        emit SetDistributor(_distributor);
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MODIFIER                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) {
            NotDistributor.selector.revertWith();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBlockRewardController
    function setBaseRate(uint256 _baseRate) external onlyOwner {
        emit BaseRateChanged(baseRate, _baseRate);
        baseRate = _baseRate;
    }

    /// @inheritdoc IBlockRewardController
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        emit RewardRateChanged(rewardRate, _rewardRate);
        rewardRate = _rewardRate;
    }

    /// @inheritdoc IBlockRewardController
    function setMinBoostedRewardRate(uint256 _minBoostedRewardRate) external onlyOwner {
        emit MinBoostedRewardRateChanged(minBoostedRewardRate, _minBoostedRewardRate);
        minBoostedRewardRate = _minBoostedRewardRate;
    }

    /// @inheritdoc IBlockRewardController
    function setBoostMultiplier(uint256 _boostMultiplier) external onlyOwner {
        if (_boostMultiplier > 1e6 ether) {
            InvalidBoostMultiplier.selector.revertWith();
        }
        emit BoostMultiplierChanged(boostMultiplier, _boostMultiplier);
        boostMultiplier = _boostMultiplier;
    }

    /// @inheritdoc IBlockRewardController
    function setRewardConvexity(int256 _rewardConvexity) external onlyOwner {
        if (_rewardConvexity < 0 || _rewardConvexity > 10e18) {
            InvalidRewardConvexity.selector.revertWith();
        }
        emit RewardConvexityChanged(rewardConvexity, _rewardConvexity);
        rewardConvexity = _rewardConvexity;
    }

    /// @inheritdoc IBlockRewardController
    function setDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        emit SetDistributor(_distributor);
        distributor = _distributor;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              DISTRIBUTOR FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBlockRewardController
    function processRewards(bytes calldata pubkey, uint256 blockNumber) external onlyDistributor returns (uint256) {
        uint256 base = baseRate;
        uint256 reward = 0;

        // Calculate the boost power for the coinbase
        int256 boost = int256(bgt.normalizedBoost(pubkey));

        if (boost > 0) {
            // Calculate intermediate parameters for the reward formula
            // r = (1 + mul) * (1 - 1 / (1 + mul * boost^conv)) * rewardRate ∈ [0, mul * rewardRate]

            uint256 one = FixedPointMathLib.WAD;
            // boost^conv ∈ (0, 1]
            uint256 tmp_0 = uint256(FixedPointMathLib.powWad(boost, rewardConvexity));
            if (tmp_0 == one) {
                // avoid approx errors in the following code
                reward = FixedPointMathLib.mulWad(rewardRate, boostMultiplier);
            } else {
                // 1 + mul * boost^conv ∈ [1, 1 + mul]
                uint256 tmp_1 = one + FixedPointMathLib.mulWad(boostMultiplier, tmp_0);
                // 1 - 1 / (1 + mul * boost^conv) ∈ [0, mul / (1 + mul)]
                uint256 tmp_2 = one - FixedPointMathLib.divWad(one, tmp_1);

                // @dev Due to splitting fixed point ops, [mul / (1 + mul)] * (1 + mul) may be slightly > mul
                uint256 coeff = FixedPointMathLib.mulWad(tmp_2, one + boostMultiplier);
                if (coeff > boostMultiplier) coeff = boostMultiplier;

                reward = FixedPointMathLib.mulWad(rewardRate, coeff);
            }
        }

        if (reward < minBoostedRewardRate) reward = minBoostedRewardRate;

        // Factor in commission rate of the coinbase
        uint256 commission = bgt.commissionRewardRate(pubkey, reward);
        reward -= commission;
        emit BlockRewardProcessed(blockNumber, base, commission, reward);

        // Use the beaconDepositContract to fetch the operator, Its gauranteed to return a valid address.
        // Beacon Deposit contract will enforce validators to set an operator.
        address operator = beaconDepositContract.getOperator(pubkey);
        if (base + commission > 0) bgt.mint(operator, base + commission);

        // Mint the scaled rewards BGT for coinbase cutting board to the distributor.
        if (reward > 0) bgt.mint(distributor, reward);

        return reward;
    }
}
