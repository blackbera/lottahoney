// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { Ownable } from "solady/src/auth/Ownable.sol";

/**
 * @notice This is an ERC20 token for testing.
 * @author Berachain Team
 * @author Solady (https://github.com/Vectorized/solady/)
 */
contract MockHoney is ERC20, Ownable, UUPSUpgradeable {
    string private constant _name = "MockHoney";
    string private constant _symbol = "MOCK_HONEY";

    function initialize() public {
        super._initializeOwner(msg.sender);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function _authorizeUpgrade(address) internal view override onlyOwner {
        return;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
