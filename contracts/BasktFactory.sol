// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BasktToken} from "./BasktToken.sol";

/**
 * @title BasktFactory
 * @notice Factory contract for deploying and managing BasktToken baskets
 * @dev Handles basket creation, fee configuration, and maintains a registry of all baskets.
 *      Only owner can modify protocol-wide parameters (fees, recipients).
 *      
 *      Key Features:
 *      - Permissionless basket creation with validated composition
 *      - Protocol-wide fee configuration (applied to all new baskets)
 *      - Registry for discovering all baskets
 *      - Snapshots for tracking basket metadata
 *
 * @author Vouch - Baskt Protocol
 */
contract BasktFactory {
    
    // -------- Custom Errors (Gas Efficient) --------
    error InvalidArrayLengths();    /// Tokens and units arrays must have same length
    error TooManyAssets();          /// Maximum 10 tokens per basket
    error ZeroAddress();            /// Address parameter cannot be zero
    error ZeroValue();              /// Numeric value cannot be zero
    error NotOwner();               /// Caller is not the owner
    error DuplicateToken();         /// Same token appears twice in basket
    error BadUnit();                /// Units per share cannot be zero

    // -------- Events --------
    /**
     * @notice Emitted when a new basket is created
     * @param bucket Address of the newly deployed BasktToken
     * @param creator Address that will receive creator fees
     * @param name ERC20 name of the basket
     * @param symbol ERC20 symbol of the basket
     * @param tokens Array of underlying token addresses
     * @param unitsPerShare Array of token amounts per share
     * @param mintFeeBps Total mint fee in basis points
     * @param creatorFeeShareBps Creator's share of fees in basis points
     * @param protocolFeeRecipient Address receiving protocol fees
     */
    event BucketCreated(
        address indexed bucket,
        address indexed creator,
        string name,
        string symbol,
        address[] tokens,
        uint256[] unitsPerShare,
        uint16 mintFeeBps,
        uint16 creatorFeeShareBps,
        address protocolFeeRecipient
    );

    // -------- State Variables --------
    
    /// @notice Factory owner (can update protocol parameters)
    address public owner;
    
    /// @notice Protocol treasury address (receives protocol fee share)
    address public protocolFeeRecipient;
    
    /// @notice Protocol-wide mint fee in basis points (applied to new baskets)
    /// @dev 100 bps = 1%, capped at 1000 bps (10%) in setter
    uint16  public mintFeeBps;
    
    /// @notice Creator's share of mint fees in basis points
    /// @dev 5000 = 50% to creator, 50% to protocol. Max 10000 (100%)
    uint16  public creatorFeeShareBps;

    // -------- Registry --------
    
    /// @notice Array of all deployed basket addresses
    address[] public allBuckets;
    
    /// @notice Mapping to check if address is a valid basket
    mapping(address => bool) public isBucket;

    /// @notice Metadata snapshot for each basket (immutable after creation)
    struct Snapshot {
        address creator;                /// Basket creator
        uint16 mintFeeBps;             /// Mint fee at creation time
        uint16 creatorFeeShareBps;     /// Creator fee share at creation time
        address protocolFeeRecipient;  /// Protocol recipient at creation time
    }
    
    /// @notice Stored metadata for each basket
    mapping(address => Snapshot) public bucketSnapshot;
    
    /// @notice Maps bucket address to its creator
    mapping(address => address) public creatorOf;

    /**
     * @notice Initializes the factory with protocol parameters
     * @param _protocolFeeRecipient Address to receive protocol fees
     * @param _mintFeeBps Initial mint fee in basis points (max 1000 = 10%)
     * @param _creatorFeeShareBps Initial creator fee share (max 10000 = 100%)
     * @dev Deployer becomes owner
     */
    constructor(
        address _protocolFeeRecipient, 
        uint16 _mintFeeBps, 
        uint16 _creatorFeeShareBps
    ) {
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        owner = msg.sender;
        protocolFeeRecipient = _protocolFeeRecipient;
        _setMintFeeBps(_mintFeeBps);
        _setCreatorFeeShareBps(_creatorFeeShareBps);
    }

    // -------- Owner Controls --------
    
    /**
     * @notice Transfers ownership to a new address
     * @param _newOwner New owner address
     * @dev Only current owner can call
     */
    function setOwner(address _newOwner) external {
        if (msg.sender != owner) revert NotOwner();
        if (_newOwner == address(0)) revert ZeroAddress();
        owner = _newOwner;
    }

    /**
     * @notice Updates protocol fee recipient address
     * @param _recipient New protocol fee recipient
     * @dev Only affects new baskets. Existing baskets retain old recipient.
     */
    function setProtocolFeeRecipient(address _recipient) external {
        if (msg.sender != owner) revert NotOwner();
        if (_recipient == address(0)) revert ZeroAddress();
        protocolFeeRecipient = _recipient;
    }

    /**
     * @notice Updates protocol mint fee
     * @param _bps New mint fee in basis points (max 1000 = 10%)
     * @dev Only affects new baskets. Existing baskets retain their fee.
     */
    function setMintFeeBps(uint16 _bps) external {
        if (msg.sender != owner) revert NotOwner();
        _setMintFeeBps(_bps);
    }

    /**
     * @notice Updates creator fee share percentage
     * @param _bps New creator share in basis points (max 10000 = 100%)
     * @dev Only affects new baskets. Existing baskets retain their split.
     */
    function setCreatorFeeShareBps(uint16 _bps) external {
        if (msg.sender != owner) revert NotOwner();
        _setCreatorFeeShareBps(_bps);
    }

    /**
     * @notice Internal setter for mint fee with validation
     * @param _bps Fee in basis points
     * @dev Enforces maximum of 1000 bps (10%)
     */
    function _setMintFeeBps(uint16 _bps) internal {
        require(_bps <= 1000, "fee too high"); // Max 10% mint fee
        mintFeeBps = _bps;
    }
    
    /**
     * @notice Internal setter for creator fee share with validation
     * @param _bps Creator share in basis points
     * @dev Enforces range 0-10000 (0-100%)
     */
    function _setCreatorFeeShareBps(uint16 _bps) internal {
        require(_bps <= 10_000, "bad bps"); // Must be 0-100%
        creatorFeeShareBps = _bps;
    }

    // -------- View Functions for Applications --------
    
    /**
     * @notice Returns total number of baskets created
     * @return Number of baskets in registry
     */
    function allBucketsLength() external view returns (uint256) { 
        return allBuckets.length; 
    }

    /**
     * @notice Returns all basket addresses
     * @return Array of all basket addresses
     * @dev May be gas-intensive for large arrays. Consider using getBucketsPaged()
     */
    function getBuckets() external view returns (address[] memory) {
        return allBuckets;
    }

    /**
     * @notice Returns a paginated slice of basket addresses
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return out Array of basket addresses in range [offset, offset+limit)
     * @dev Returns empty array if offset >= total baskets
     */
    function getBucketsPaged(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory out)
    {
        uint256 n = allBuckets.length;
        if (offset >= n) {
            return new address[](0); // Empty array if offset out of bounds
        }
        
        // Calculate actual range
        uint256 end = offset + limit;
        if (end > n) end = n;

        // Build result array
        out = new address[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            out[i - offset] = allBuckets[i];
        }
    }

    /**
     * @notice Returns immutable metadata for a basket
     * @param bucket Basket address to query
     * @return s Snapshot struct containing creator, fees, and recipient
     * @dev Returns zero values if bucket doesn't exist
     */
    function getBucketSnapshot(address bucket)
        external
        view
        returns (Snapshot memory s)
    {
        return bucketSnapshot[bucket];
    }

    // -------- Basket Creation --------
    
    /**
     * @notice Creates a new basket token with specified composition
     * @param tokens Array of underlying ERC20 addresses (max 10, no duplicates, non-zero)
     * @param unitsPerShare Amount of each token per 1e18 shares (all must be > 0)
     * @param name ERC20 name for the basket (e.g., "Blue Chip DeFi Basket")
     * @param symbol ERC20 symbol for the basket (e.g., "DEFI")
     * @param creator Address that will receive creator fees (cannot be zero)
     * @return bucket Address of the newly deployed BasktToken
     * 
     * @dev Validation performed:
     *      - Arrays must have same length and contain 1-10 tokens
     *      - No zero addresses or zero units
     *      - No duplicate tokens (O(n²) check, acceptable for n≤10)
     *      
     * @dev Basket is deployed with current factory parameters (fees, recipient)
     *      These parameters are immutable in the basket contract
     *      
     * @dev Emits BucketCreated event with all basket parameters
     */
    function createBucket(
        address[] calldata tokens,
        uint256[] calldata unitsPerShare,
        string calldata name,
        string calldata symbol,
        address creator
    ) external returns (address bucket) {
        // Validate array inputs
        if (tokens.length == 0 || tokens.length != unitsPerShare.length) {
            revert InvalidArrayLengths();
        }
        if (tokens.length > 10) revert TooManyAssets();
        if (creator == address(0)) revert ZeroAddress();

        // Validate each token and unit (O(n²) duplicate check is fine for n≤10)
        for (uint256 i = 0; i < tokens.length; ++i) {
            address t = tokens[i];
            
            // Check token address is valid
            if (t == address(0)) revert ZeroAddress();
            
            // Check units per share is non-zero
            if (unitsPerShare[i] == 0) revert BadUnit();
            
            // Check for duplicate tokens
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                if (t == tokens[j]) revert DuplicateToken();
            }
        }

        // Deploy new BasktToken with current factory parameters
        bucket = address(new BasktToken(
            name,
            symbol,
            tokens,
            unitsPerShare,
            creator,
            protocolFeeRecipient,  // Current protocol recipient (immutable in basket)
            mintFeeBps,            // Current mint fee (immutable in basket)
            creatorFeeShareBps,    // Current creator share (immutable in basket)
            msg.sender             // Deployer (not used in basket, but tracked)
        ));

        // Register basket in factory
        isBucket[bucket] = true;
        allBuckets.push(bucket);
        creatorOf[bucket] = creator;
        
        // Store immutable snapshot of creation parameters
        bucketSnapshot[bucket] = Snapshot({
            creator: creator,
            mintFeeBps: mintFeeBps,
            creatorFeeShareBps: creatorFeeShareBps,
            protocolFeeRecipient: protocolFeeRecipient
        });

        // Emit event for indexing and discovery
        emit BucketCreated(
            bucket,
            creator,
            name,
            symbol,
            tokens,
            unitsPerShare,
            mintFeeBps,
            creatorFeeShareBps,
            protocolFeeRecipient
        );
    }
}
