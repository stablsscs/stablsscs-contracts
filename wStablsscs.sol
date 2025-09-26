pragma solidity =0.8.22;

import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WStablsscs is ERC20Permit {
    IStablsscs public immutable Stablsscs;

    event DestroyedBlackFunds(address indexed blackListedUser, uint256 amount);

    modifier notBlacklisted(address _from, address _to) {
        require(!Stablsscs.isBlackListed(_from) && !Stablsscs.isBlackListed(_to), "User blacklisted");
        _;
    }

    modifier whenNotPaused() {
        require(!Stablsscs.paused(), "protocol paused");
        _;
    }

    /**
     * @param _Stablsscs address of the Stablsscs token to wrap
     */
    constructor(IStablsscs _Stablsscs)
        ERC20Permit("Wrapped Stablsscs 1.0")
        ERC20("Wrapped Stablsscs 1.0", "wStablsscs")
    {
        Stablsscs = _Stablsscs;
    }

    /**
     * @notice Exchanges Stablsscs to wStablsscs
     * @param _StablsscsAmount amount of Stablsscs to wrap in exchange for wStablsscs
     * @dev Requirements:
     *  - `_StablsscsAmount` must be non-zero
     *  - msg.sender must approve at least `_StablsscsAmount` Stablsscs to this
     *    contract.
     *  - msg.sender must have at least `_StablsscsAmount` of Stablsscs.
     * User should first approve _StablsscsAmount to the wStablsscs contract
     * @return Amount of wStablsscs user receives after wrap
     */
    function wrap(uint256 _StablsscsAmount) external returns (uint256) {
        require(_StablsscsAmount > 0, "wStablsscs: can't wrap zero Stablsscs");
        uint256 wStablsscsAmount = Stablsscs.getScaledAmount(_StablsscsAmount);
        _mint(msg.sender, wStablsscsAmount);
        Stablsscs.transferFrom(msg.sender, address(this), _StablsscsAmount);
        return wStablsscsAmount;
    }

    /**
     * @notice Exchanges wStablsscs to Stablsscs
     * @param _wStablsscsAmount amount of wStablsscs to uwrap in exchange for Stablsscs
     * @dev Requirements:
     *  - `_wStablsscsAmount` must be non-zero
     *  - msg.sender must have at least `_wStablsscsAmount` wStablsscs.
     * @return Amount of Stablsscs user receives after unwrap
     */
    function unwrap(uint256 _wStablsscsAmount) external returns (uint256) {
        require(_wStablsscsAmount > 0, "wStablsscs: zero amount unwrap not allowed");
        uint256 StablsscsAmount = Stablsscs.getLiquidityAmount(_wStablsscsAmount);
        _burn(msg.sender, _wStablsscsAmount);
        Stablsscs.transfer(msg.sender, StablsscsAmount);
        return StablsscsAmount;
    }

    function destroyBlackFunds(address _blackListedUser) public {
        require(msg.sender == Stablsscs.compliance(), "not compliance");
        require(Stablsscs.isBlackListed(_blackListedUser), "user should be blacklisted");
        uint256 dirtyShares = balanceOf(_blackListedUser);
        uint256 StablsscsAmount = Stablsscs.getLiquidityAmount(dirtyShares);
        _burn(_blackListedUser, dirtyShares);
        require(StablsscsAmount > 0, "cannot destroy 0 black funds");
        Stablsscs.transfer(Stablsscs.owner(), StablsscsAmount);
        emit DestroyedBlackFunds(_blackListedUser, dirtyShares);
    }

    function transfer(address to, uint256 value) public override whenNotPaused notBlacklisted(msg.sender, to) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override whenNotPaused notBlacklisted(from, to) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    receive() external payable {}

    /**
     * @notice Get amount of wStablsscs for a given amount of Stablsscs
     * @param _StablsscsAmount amount of Stablsscs
     * @return Amount of wStablsscs for a given Stablsscs amount
     */
    function getwStablsscsByStablsscs(uint256 _StablsscsAmount) public view returns (uint256) {
        return Stablsscs.getScaledAmount(_StablsscsAmount);
    }

    /**
     * @notice Get amount of Stablsscs for a given amount of wStablsscs
     * @param _wStablsscsAmount amount of wStablsscs
     * @return Amount of Stablsscs for a given wStablsscs amount
     */
    function getStablsscsBywStablsscs(uint256 _wStablsscsAmount) external view returns (uint256) {
        return Stablsscs.getLiquidityAmount(_wStablsscsAmount);
    }

    /**
     * @notice Get amount of Stablsscs for a one wStablsscs
     * @return Amount of Stablsscs for 1 wStablsscs
     */
    function StablsscsPerToken() external view returns (uint256) {
        return Stablsscs.getLiquidityAmount(1e6);
    }

    /**
     * @notice Get amount of wStablsscs for a one Stablsscs
     * @return Amount of wStablsscs for a 1 Stablsscs
     */
    function tokensPerStablsscs() external view returns (uint256) {
        return Stablsscs.getScaledAmount(1e6);
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
}


interface IStablsscs is IERC20 {
    function getScaledAmount(uint256 amount) external view returns (uint256);
    function getLiquidityAmount(uint256 shares) external view returns (uint256);
    function isBlackListed(address user) external view returns (bool);
    function paused() external view returns (bool);
    function owner() external view returns (address);
    function compliance() external view returns (address);
}