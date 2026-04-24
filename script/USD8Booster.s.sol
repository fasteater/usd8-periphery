// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {USD8Booster} from "../src/USD8Booster.sol";

contract DeployUSD8Booster is Script {
    function run() external returns (USD8Booster booster) {
        string memory uri = vm.envOr("BOOSTER_URI", string("ipfs://usd8-booster/{id}.json"));
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        booster = new USD8Booster(uri);
        vm.stopBroadcast();

        console2.log("USD8Booster deployed at:", address(booster));
    }
}
