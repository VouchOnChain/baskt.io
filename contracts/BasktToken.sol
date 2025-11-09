// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20}  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BasktToken
 * @notice ERC20 token representing a basket of multiple underlying ERC20 tokens
 * @dev Each BasktToken represents a fixed proportion of underlying tokens (unitsPerShare).
 *      Users mint by depositing proportional amounts of all underlying tokens.
 *      Users redeem by burning BasktTokens to receive proportional underlying tokens.
 *      
 *      Fee Structure:
 *      - Mint fees are charged in shares (not underlying tokens)
 *      - Fees are split between basket creator and protocol
 *      - All fee parameters are immutable (set at deployment)
 *
 * @author Vouch - Baskt Protocol
 */
contract BasktToken is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------- Immutable Configuration --------
    /// @notice Address of the basket creator (receives creator fee share)
    address public immutable creator;
    
    /// @notice Protocol treasury address (receives protocol fee share)
    address public immutable protocolFeeRecipient;
    
    /// @notice Total mint fee in basis points (1 bps = 0.01%)
    /// @dev Applied to minted shares, then split between creator and protocol
    uint16  public immutable mintFeeBps;
    
    /// @notice Creator's share of mint fees in basis points (out of 10000)
    /// @dev Remaining fees go to protocol. Example: 5000 = 50% to creator, 50% to protocol
    uint16  public immutable creatorFeeShareBps;

    // -------- Basket Composition --------
    /// @notice Array of underlying ERC20 token addresses in this basket
    address[] public tokens;
    
    /// @notice Amount of each token required per 1e18 (ONE) basket shares
    /// @dev Stored in each token's native decimals. Index matches tokens[] array
    uint256[] public unitsPerShare;

    // -------- Constants --------
    /// @notice Scaling factor for share calculations (1e18 = 1 full share)
    uint256 private constant ONE = 1e18;
    
    /// @notice Minimum shares for mint/redeem to prevent dust attacks
    /// @dev 1e12 = 0.000001 shares minimum (1 millionth of a share)
    uint256 private constant MIN_SHARE = 1e12;

    /**
     * @notice Initializes a new BasktToken with specified composition and fee structure
     * @param name_ ERC20 token name
     * @param symbol_ ERC20 token symbol
     * @param _tokens Array of underlying token addresses (must be non-zero, no duplicates)
     * @param _unitsPerShare Array of token amounts per 1e18 shares (must be > 0)
     * @param _creator Basket creator address (receives creator fees)
     * @param _protocolFeeRecipient Protocol treasury address
     * @param _mintFeeBps Total mint fee in basis points (e.g., 100 = 1%)
     * @param _creatorFeeShareBps Creator's share of fees in basis points (e.g., 5000 = 50%)
     * @dev Called by BasktFactory. Validation of tokens/units is done in factory
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory _tokens,
        uint256[] memory _unitsPerShare,
        address _creator,
        address _protocolFeeRecipient,
        uint16 _mintFeeBps,
        uint16 _creatorFeeShareBps,
        address /*deployer*/
    ) ERC20(name_, symbol_) {
        require(_creator != address(0) && _protocolFeeRecipient != address(0), "zero addr");
        require(_tokens.length == _unitsPerShare.length && _tokens.length > 0, "bad arrays");
        
        creator = _creator;
        protocolFeeRecipient = _protocolFeeRecipient;
        mintFeeBps = _mintFeeBps;
        creatorFeeShareBps = _creatorFeeShareBps;

        tokens = _tokens;
        unitsPerShare = _unitsPerShare;

        // Note: Factory enforces non-zero addresses, no duplicates, and units > 0
    }

    // -------- View Functions --------
    
    /**
     * @notice Returns the basket composition (tokens and their units per share)
     * @return Array of token addresses and array of units per share
     * @dev Useful for frontends to display basket contents and calculate deposits
     */
    function getComposition() external view returns (address[] memory, uint256[] memory) {
        return (tokens, unitsPerShare);
    }

    /**
     * @notice Calculates required underlying tokens for minting a given amount of shares
     * @param shares Amount of basket tokens to mint (in 1e18 decimals)
     * @return req Array of token amounts required (in each token's native decimals)
     * @dev Rounds UP to ensure sufficient backing. Reverts if any leg would be zero.
     */
    function previewDeposit(uint256 shares) public view returns (uint256[] memory req) {
        require(shares >= MIN_SHARE, "shares too small");
        uint256 len = tokens.length;
        req = new uint256[](len);
        
        for (uint256 i = 0; i < len; ++i) {
            // Round UP: ensures user deposits enough to fully back their shares
            req[i] = _mulDivUp(unitsPerShare[i], shares, ONE);
            require(req[i] > 0, "zero leg"); // Prevents dust exploits
        }
    }

    /**
     * @notice Calculates underlying tokens returned when redeeming shares
     * @param shares Amount of basket tokens to redeem (in 1e18 decimals)
     * @return out Array of token amounts user will receive (in each token's native decimals)
     * @dev Rounds DOWN for solvency. May return 0 for very small share amounts.
     */
    function previewRedeem(uint256 shares) public view returns (uint256[] memory out) {
        require(shares >= MIN_SHARE, "shares too small");
        uint256 len = tokens.length;
        out = new uint256[](len);
        
        for (uint256 i = 0; i < len; ++i) {
            // Round DOWN: safe for protocol (user gets slightly less on tiny redeems)
            out[i] = (unitsPerShare[i] * shares) / ONE;
        }
    }

    // -------- Core Functions --------

    /**
     * @notice Mints basket tokens by depositing proportional underlying tokens
     * @param sharesDesired Amount of basket tokens to mint (before fees)
     * @param to Address to receive the minted basket tokens
     * @dev Process:
     *      1. Calculate required underlying tokens (rounded up)
     *      2. Pull tokens from msg.sender
     *      3. Calculate fee in shares (deducted from sharesDesired)
     *      4. Split fee between creator and protocol
     *      5. Mint net shares to user, fee shares to creator/protocol
     * 
     * @dev Emits Transfer events for all mints (user, creator, protocol)
     * @dev Requires msg.sender to have approved this contract for all underlying tokens
     */
    function mint(uint256 sharesDesired, address to) external nonReentrant {
        require(to != address(0), "bad to");
        require(sharesDesired >= MIN_SHARE, "shares too small");

        uint256 len = tokens.length;
        uint256[] memory req = new uint256[](len);

        // 1) Calculate required underlyings for FULL gross sharesDesired (before fees)
        for (uint256 i = 0; i < len; ++i) {
            uint256 r = _mulDivUp(unitsPerShare[i], sharesDesired, ONE);
            require(r > 0, "zero leg");
            req[i] = r;
        }

        // 2) Pull all required underlying tokens from user
        for (uint256 i = 0; i < len; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), req[i]);
        }

        // 3) Calculate fee in SHARES (not underlying tokens)
        //    Fee is taken from sharesDesired, backing remains 100%
        uint256 feeShares = (mintFeeBps == 0)
            ? 0
            : _mulDivUp(sharesDesired, mintFeeBps, 10_000); // Round up to favor backing

        // User receives sharesDesired minus fees
        uint256 userShares = sharesDesired - feeShares;
        require(userShares > 0, "fee >= shares");

        // 4) Split fee between creator and protocol
        uint256 creatorCut = (creatorFeeShareBps == 0)
            ? 0
            : _mulDivUp(feeShares, creatorFeeShareBps, 10_000); // Round up to avoid dust
        uint256 protocolCut = feeShares - creatorCut;

        // 5) Mint exactly sharesDesired total: maintains 1:1 backing with deposited tokens
        _mint(to, userShares);
        if (creatorCut > 0) _mint(creator, creatorCut);
        if (protocolCut > 0) _mint(protocolFeeRecipient, protocolCut);

        // Total supply increased by exactly sharesDesired, matching pulled underlyings
    }

    /**
     * @notice Redeems basket tokens for proportional underlying tokens
     * @param shares Amount of basket tokens to burn
     * @param to Address to receive the underlying tokens
     * @dev Burns shares from msg.sender and transfers proportional underlying tokens to `to`
     * @dev No redemption fee currently implemented (could be added if needed)
     * @dev Amounts are rounded down, so tiny redeems may return 0 for some tokens
     */
    function redeem(uint256 shares, address to) external nonReentrant {
        require(to != address(0), "bad to");
        require(shares >= MIN_SHARE, "shares too small");

        // Burn shares from msg.sender
        _burn(msg.sender, shares);

        // Transfer proportional underlying tokens to recipient
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 amt = (unitsPerShare[i] * shares) / ONE; // Round down for solvency
            if (amt > 0) IERC20(tokens[i]).safeTransfer(to, amt);
        }
        
        // Note: Could implement redeem fee here if needed (charge in shares before burn)
    }

    // -------- Internal Utilities --------
    
    /**
     * @notice Multiplies two numbers and divides by denominator, rounding UP
     * @param a First multiplicand
     * @param b Second multiplicand  
     * @param denom Denominator
     * @return Result of (a * b) / denom, rounded up
     * @dev Used for mint calculations to ensure sufficient backing
     * @dev Returns 0 if a * b == 0 (no rounding needed)
     */
    function _mulDivUp(uint256 a, uint256 b, uint256 denom) internal pure returns (uint256) {
        unchecked {
            uint256 prod = a * b;
            // If product is 0, result is 0 (no rounding needed)
            // Otherwise: (prod + denom - 1) / denom rounds up
            return prod == 0 ? 0 : (prod + denom - 1) / denom;
        }
    }
}
