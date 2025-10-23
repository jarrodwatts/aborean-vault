// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AboreanVault} from "../src/Vault.sol";

/**
 * @title DeployVault
 * @notice Deployment script for AboreanVault on Abstract L2
 * 
 * Usage:
 * 
 * Testnet:
 * forge script script/Deploy.s.sol:DeployVault --rpc-url https://api.testnet.abs.xyz --broadcast --verify --zksync
 * 
 * Mainnet:
 * forge script script/Deploy.s.sol:DeployVault --rpc-url https://api.mainnet.abs.xyz --broadcast --verify --zksync
 * 
 * Dry run (simulation):
 * forge script script/Deploy.s.sol:DeployVault --rpc-url https://api.mainnet.abs.xyz --zksync
 */
contract DeployVault is Script {
    // Abstract Mainnet Addresses
    address constant WETH = 0x3439153EB7AF838Ad19d56E1571FBD09333C2809;
    address constant PENGU = 0x9eBe3A824Ca958e4b3Da772D2065518F009CBa62;
    address constant POSITION_MANAGER = 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F;
    address constant GAUGE = 0x125c13e12bD40BC7EB4F129d3f8443091D443B7E;
    address constant ROUTER = 0xE8142D2f82036B6FC1e79E4aE85cF53FBFfDC998;
    address constant POOL = 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC;
    address constant PYTH = 0x8739d5024B5143278E2b15Bd9e7C26f6CEc658F1;
    address constant VOTING_ESCROW = 0x27B04370D8087e714a9f557c1EFF7901cea6bB63;
    address constant VOTER = 0xC0F53703e9f4b79fA2FB09a2aeBA487FA97729c9;

    function run() external returns (AboreanVault vault) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=================================================");
        console2.log("Deploying AboreanVault to Abstract");
        console2.log("=================================================");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // Display contract addresses
        console2.log("Contract Addresses:");
        console2.log("-------------------");
        console2.log("WETH:           ", WETH);
        console2.log("PENGU:          ", PENGU);
        console2.log("Position Mgr:   ", POSITION_MANAGER);
        console2.log("Gauge:          ", GAUGE);
        console2.log("Router:         ", ROUTER);
        console2.log("Pool:           ", POOL);
        console2.log("Pyth:           ", PYTH);
        console2.log("VotingEscrow:   ", VOTING_ESCROW);
        console2.log("Voter:          ", VOTER);
        console2.log("");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy vault
        console2.log("Deploying vault...");
        vault = new AboreanVault(
            WETH,
            PENGU,
            POSITION_MANAGER,
            GAUGE,
            ROUTER,
            POOL,
            PYTH,
            VOTING_ESCROW,
            VOTER
        );

        console2.log("");
        console2.log("=================================================");
        console2.log("Deployment Successful!");
        console2.log("=================================================");
        console2.log("Vault Address:  ", address(vault));
        console2.log("Vault Owner:    ", vault.owner());
        console2.log("Vault Name:     ", vault.name());
        console2.log("Vault Symbol:   ", vault.symbol());
        console2.log("");

        vm.stopBroadcast();

        // Post-deployment information
        console2.log("=================================================");
        console2.log("Next Steps:");
        console2.log("=================================================");
        console2.log("1. Verify contract on Abscan:");
        console2.log("   forge verify-contract", address(vault), "src/Vault.sol:AboreanVault --chain abstractMainnet --watch --zksync");
        console2.log("");
        console2.log("2. Test basic functionality:");
        console2.log("   - Deposit WETH");
        console2.log("   - Wait for rewards");
        console2.log("   - Call harvest()");
        console2.log("   - Call lockABX()");
        console2.log("   - Call voteForPool()");
        console2.log("");
        console2.log("3. Set up automation for:");
        console2.log("   - harvest() (daily)");
        console2.log("   - lockABX() (daily)");
        console2.log("   - voteForPool() (weekly, Thursdays)");
        console2.log("   - compound() (weekly)");
        console2.log("");
        console2.log("4. Monitor vault health:");
        console2.log("   - Check position is in range");
        console2.log("   - Monitor TVL growth");
        console2.log("   - Track APR");
        console2.log("=================================================");

        return vault;
    }
}

