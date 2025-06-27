// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library DeploymentConstants {
    // Fork configuration
    uint256 constant FORK_BLOCK = 22496625;
    address constant FORK_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant FORK_DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Existing contract addresses
    address constant LRT_SQUARED_PROXY = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address constant GOVERNOR = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;
    address constant TREASURY = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;

    // Token addresses (in order of registration)
    address constant EIGEN = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address constant ETHFI = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant sETHFI = 0x86B5780b606940Eb59A062aA85a07959518c0161;
    address constant eEIGEN = 0xE77076518A813616315EaAba6cA8e595E845EeE9;
    address constant SWELL = 0x0a6E7Ba5042B38349e437ec6Db6214AEC7B35676;

    // Existing strategies (to be replaced)
    address constant OLD_SETHFI_STRATEGY = 0x76C57e359C0eDA0aac54d97832fb1b4451805aD8;
    address constant OLD_EEIGEN_STRATEGY = 0x2F2342BD9fca72887f46De9522014f4cd154Cf3e;

    // Price providers and accountants
    address constant PRICE_PROVIDER = 0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3;
    address constant BORING_VAULT_PRICE_PROVIDER = 0x130e22952DD3DE2c80EBdFC2B256E344ff3A0729;

    // Withdrawal queues
    address constant sETHFI_QUEUE = 0xD45884B592E316eB816199615A95C182F75dea07;
    address constant eEIGEN_QUEUE = 0x1C3e15448b9a600dfC8bDfeb495EB4B3B62cd55f;

    // Storage slots
    bytes32 constant GOVERNOR_SLOT = 0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87;
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant ADMIN_IMPL_SLOT = 0x67f3bdb99ec85305417f06f626cf52c7dee7e44607664b5f1cce0af5d822472f;
}
