pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
contract Dikasteria is ERC20PresetMinterPauser {
	constructor() ERC20PresetMinterPauser("Dikasteria", "DIKA") {
		mint(address(this), 69420000); //69,420,000
	}
}