// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ApeRouter} from "./ApeRouter.sol";
interface IApePairFactoryLike {
    enum PairVariant {
        BAYC_ApeCoin,
        MAYC_ApeCoin,
    }

    function protocolFeeMultiplier() external view returns (uint256);
    function protocolFeeRecipient() external view returns (address payable);
    function callAllowed(address target) external view returns (bool);
    function routerStatus(ApeRouter router)
        external
        view
        returns (bool allowed, bool wasEverAllowed);

    function isPair(address potentialPair, PairVariant variant)
        external
        view
        returns (bool);
}

