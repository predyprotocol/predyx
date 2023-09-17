// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/ISupplyToken.sol";

contract SupplyToken is ERC20, ISupplyToken {
    address immutable controller;
    uint8 _decimals;

    modifier onlyController() {
        require(controller == msg.sender, "ST0");
        _;
    }

    constructor(address _controller, string memory _name, string memory _symbol, uint8 __decimals)
        ERC20(_name, _symbol)
    {
        controller = _controller;
        _decimals = __decimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external virtual override onlyController {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external virtual override onlyController {
        _burn(account, amount);
    }
}
