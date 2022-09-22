// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
// @dev Solmate's ERC20 is used instead of OZ's ERC20 so we can use safeTransferLib for cheaper safeTransfers for
// ETH and ERC20 tokens
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ApePairApeCoin} from "./ApePairApeCoin.sol";
import {ApeRouter} from "./ApeRouter.sol";
import {ApePairCloner} from "./lib/ApePairCloner.sol";
import {BAYCPairApeCoin} from "./BAYCPairApeCoin.sol";
import {MAYCPairApeCoin} from "./MAYCPairApeCoin.sol";

contract ApePairFactory is Ownable, IApePairFactoryLike {
    using ApePairCloner for address;
    using SafeTransferLib for address payable;
    using SafeTransferLib for ERC20;

    bytes4 private constant INTERFACE_ID_ERC721_ENUMERABLE =
        type(IERC721Enumerable).interfaceId;
    uint256 internal constant MAX_PROTOCOL_FEE = 0.10e18; // 10%, must <= 1 - MAX_FEE
    ApeBAYC_ApeCoin public immutable BAYC_ApeCoin;
    ApeMAYC_ApeCoin public immutable MAYC_ApeCoin;
    address payable public override protocolFeeRecipient;

    // Units are in base 1e18
    uint256 public override protocolFeeMultiplier;
    mapping(address => bool) public override callAllowed;
    struct RouterStatus {
        bool allowed;
        bool wasEverAllowed;
    }
    mapping(ApeRouter => RouterStatus) public override routerStatus;
    event NewPair(address poolAddress);
    event TokenDeposit(address poolAddress);
    event NFTDeposit(address poolAddress);
    event ProtocolFeeRecipientUpdate(address recipientAddress);
    event ProtocolFeeMultiplierUpdate(uint256 newMultiplier);
    event CallTargetStatusUpdate(address target, bool isAllowed);
    event RouterStatusUpdate(ApeRouter router, bool isAllowed);

    constructor(
        MAYC_ApeCoin _MAYC_ApeCoin,
        ApeBAYC_ApeCoin _ApeBAYC_ApeCoin,
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeMultiplier,
    ) {
        MAYC_ApeCoinTemplate = _MAYC_ApeCoinTemplate;
        BAYC_ApeCoinTemplate = _BAYC_ApeCoinTemplate;
        protocolFeeRecipient = _protocolFeeRecipient;
        require(_protocolFeeMultiplier <= MAX_PROTOCOL_FEE, "Fee too large");
        protocolFeeMultiplier = _protocolFeeMultiplier;
    }

    /**
     * External functions
     */

    /**
        @notice Creates a BAYC+APECOIN pair contract using EIP-1167.
        @param _nft The BAYC NFT contract of the collection the pair trades
        @param _assetRecipient The address that will receive the assets and will be sent to the pool address.
        @param _staking_duration The staking duration for staking
        @param _initialNFTID The ID of NFT to transfer from the sender to the pair
        @return pair The new pair
     */

    function createBAYCPair(
        IERC721 _nft,
        address _assetRecipient,
        uint96 _staking_duration,
        uint256 _initialNFTID
    ) external returns (ApePairApeCoin pair) {

        template = address(BAYC_ApeCoinTemplate);
        pair = ApePairApeCoin(
            payable(
                template.cloneBAYCPair(
                    this,
                    _staking_duration,
                    _nft,
                )
            )
        );

        _initializePairBAYC(
            pair,
            _nft,
            _assetRecipient,
            _staking_duration,
            _initialNFTID
        );
        emit NewPair(address(pair));
    }

    /**
        @notice Creates a MAYC+APECOIN pair contract using EIP-1167.
        @param _nft The MAYC NFT contract of the collection the pair trades
        @param _assetRecipient The address that will receive the assets and will be sent to the pool address.
        @param _staking_duration The staking duration for staking
        @param _initialNFTID The ID of NFT to transfer from the sender to the pair
        @return pair The new pair
     */
 
     function createMAYCPair(
        IERC721 _nft,
        address  _assetRecipient,
        uint96 _staking_duration,
        uint256 _initialNFTID
    ) external returns (ApePairApeCoin pair) {

        template = address(MAYC_ApeCoinTemplate);
        pair = ApePairApeCoin(
            payable(
                template.cloneMAYCPair(
                    this,
                    _staking_duration,
                    _nft,
                )
            )
        );

        _initializePairMAYC(
            pair,
            _nft,
            _assetRecipient,
            _staking_duration,
            _initialNFTID
        );
        emit NewPair(address(pair));
    }


    /**
        @notice Checks if an address is a ApePair. Uses the fact that the pairs are EIP-1167 minimal proxies.
        @param potentialPair The address to check
        @param variant The pair variant (NFT is BAYC or MAYC)
        @return True if the address is the specified pair variant, false otherwise
     */
    function isPair(address potentialPair, PairVariant variant)
        public
        view
        override
        returns (bool)
    {
        if (variant == PairVariant.BAYC_ApeCoin) {
            return
                ApePairCloner.isBAYC_ApeCoin(
                    address(this),
                    address(BAYC_ApeCoinTemplate),
                    potentialPair
                );
        } else if (variant == PairVariant.MAYC_ApeCoin) {
            return
                ApePairCloner.isERC20PairClone(
                    address(this),
                    address(MAYC_ApeCoinTemplate),
                    potentialPair
                );
        } else {
            // invalid input
            return false;
        }
    }

    /**
        @notice Allows receiving ETH in order to receive protocol fees
     */
    receive() external payable {}

    /**
     * Admin functions
     */

    /**
        @notice Withdraws the ETH balance to the protocol fee recipient.
        Only callable by the owner.
     */
    function withdrawETHProtocolFees() external onlyOwner {
        protocolFeeRecipient.safeTransferETH(address(this).balance);
    }

    /**
        @notice Withdraws ERC20 tokens to the protocol fee recipient. Only callable by the owner.
        @param token The token to transfer
        @param amount The amount of tokens to transfer
     */
    function withdrawERC20ProtocolFees(ERC20 token, uint256 amount)
        external
        onlyOwner
    {
        token.safeTransfer(protocolFeeRecipient, amount);
    }

    /**
        @notice Changes the protocol fee recipient address. Only callable by the owner.
        @param _protocolFeeRecipient The new fee recipient
     */
    function changeProtocolFeeRecipient(address payable _protocolFeeRecipient)
        external
        onlyOwner
    {
        require(_protocolFeeRecipient != address(0), "0 address");
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdate(_protocolFeeRecipient);
    }

    /**
        @notice Changes the protocol fee multiplier. Only callable by the owner.
        @param _protocolFeeMultiplier The new fee multiplier, 18 decimals
     */
    function changeProtocolFeeMultiplier(uint256 _protocolFeeMultiplier)
        external
        onlyOwner
    {
        require(_protocolFeeMultiplier <= MAX_PROTOCOL_FEE, "Fee too large");
        protocolFeeMultiplier = _protocolFeeMultiplier;
        emit ProtocolFeeMultiplierUpdate(_protocolFeeMultiplier);
    }

    /**
        @notice Sets the whitelist status of a contract to be called arbitrarily by a pair.
        Only callable by the owner.
        @param target The target contract
        @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setCallAllowed(address payable target, bool isAllowed)
        external
        onlyOwner
    {
        // ensure target is not / was not ever a router
        if (isAllowed) {
            require(
                !routerStatus[ApeRouter(target)].wasEverAllowed,
                "Can't call router"
            );
        }

        callAllowed[target] = isAllowed;
        emit CallTargetStatusUpdate(target, isAllowed);
    }

    /**
        @notice Updates the router whitelist. Only callable by the owner.
        @param _router The router
        @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setRouterAllowed(ApeRouter _router, bool isAllowed)
        external
        onlyOwner
    {
        // ensure target is not arbitrarily callable by pairs
        if (isAllowed) {
            require(!callAllowed[address(_router)], "Can't call router");
        }
        routerStatus[_router] = RouterStatus({
            allowed: isAllowed,
            wasEverAllowed: true
        });

        emit RouterStatusUpdate(_router, isAllowed);
    }

    /**
     * Internal functions
     */

    function _initializePairBAYC(
        ApePairApeCoin _pair,
        IERC721 _nft,
        address _assetRecipient,
        uint128 _staking_duration,
        uint256  _initialNFTID
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _staking_duration);
        // transfer initial NFT from sender to pair
        _nft.safeTransferFrom(
            msg.sender,
            address(_pair),
            _initialNFTID
        );
    }

    function _initializePairMAYC(
        ApePairApeCoin _pair,
        IERC721 _nft,
        address _assetRecipient,
        uint128 _staking_duration,
        uint256  _initialNFTID
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _staking_duration);
        // transfer initial NFT from sender to pair
        _nft.safeTransferFrom(
            msg.sender,
            address(_pair),
            _initialNFTID
        );
    }

    /** 
      @dev Used to deposit NFT into a pair after creation and emit an event for indexing (if recipient is indeed a pair)
    */
    function depositNFTs(
        IERC721 _nft,
        uint256 id,
        address recipient
    ) external {
        // transfer NFTs from caller to recipient
            _nft.safeTransferFrom(msg.sender, recipient, ids);
        if (
            isPair(recipient, PairVariant.BAYC_ApeCoin) ||
            isPair(recipient, PairVariant.MAYC_ApeCoin) 
        ) {
            emit NFTDeposit(recipient);
        }
    }

    /**
      @dev Used to deposit ERC20s into a pair after creation and emit an event for indexing (if recipient is indeed an ERC20 pair and the token matches)
     */
    function depositERC20(
        ERC20 token,
        address recipient,
        uint256 amount
    ) external {
        token.safeTransferFrom(msg.sender, recipient, amount);
        if (
            isPair(recipient, PairVariant.BAYC_ApeCoin) ||
            isPair(recipient, PairVariant.MAYC_ApeCoin)
        ) {
            if (token == ApePairERC20(recipient).token()) {
                emit TokenDeposit(recipient);
            }
        }
    }
}