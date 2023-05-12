// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {XERC20, IXERC20} from 'contracts/XERC20.sol';
import {IXERC20Factory} from 'interfaces/IXERC20Factory.sol';
import {XERC20Lockbox} from 'contracts/XERC20Lockbox.sol';
import {CREATE3} from 'isolmate/utils/CREATE3.sol';

contract XERC20Factory is IXERC20Factory {
  // address maps to the index inside the array
  mapping(address => bool) public xerc20Registry;
  // address of the xerc20 maps to its corresponding lockbox
  mapping(address => address) public lockboxRegistry;

  address[] public lockboxRegistryArray;
  address[] public xerc20RegistryArray;

  /**
   * @notice Deploys an XERC20 contract using CREATE2
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
   * @param _baseToken The address of the base ERC20 token if you are deploying a lockbox (optional, put address(0) if you dont want to deploy one)
   */

  function deploy(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    address _baseToken
  ) external returns (address _xerc20, address _lockbox) {
    if (_baseToken != address(0)) {
      bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
      address _preComputedXERC20 = CREATE3.getDeployed(_salt);
      _lockbox = _deployLockbox(_preComputedXERC20, _baseToken);
    }

    _xerc20 = _deployXERC20(_name, _symbol, _minterLimits, _burnerLimits, _bridges, _lockbox);
  }

  /**
   * @notice Deploys an XERC20Lockbox contract using CREATE3
   *
   * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
   * @param _baseToken The address of the base token that you want to lock
   */

  function deployLockbox(address _xerc20, address _baseToken) external returns (address _lockbox) {
    if (_xerc20 == address(0) || _baseToken == address(0)) revert IXERC20Factory_TokenZeroAddress();
    if (XERC20(_xerc20).owner() != msg.sender) revert IXERC20Factory_NotOwner();
    if (lockboxRegistry[_xerc20] != address(0)) revert IXERC20Factory_LockboxAlreadyDeployed();

    _lockbox = _deployLockbox(_xerc20, _baseToken);
  }

  /**
   * @notice Deploys an XERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of burners that you are adding (optional, can be an empty array)
   * @param _lockbox The address of the lockbox (If no lockbox is deployed will be address(0))
   */

  function _deployXERC20(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    address _lockbox
  ) internal returns (address _xerc20) {
    bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
    bytes memory _creation = type(XERC20).creationCode;
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_name, _symbol, address(this)));

    _xerc20 = CREATE3.deploy(_salt, _bytecode, 0);

    xerc20RegistryArray.push(_xerc20);
    xerc20Registry[_xerc20] = true;

    // if the user inputs empty arrays we dont waste gas calling these functions
    if (_minterLimits.length == _bridges.length && _minterLimits.length != 0) {
      XERC20(_xerc20).createMinterLimits(_minterLimits, _bridges);
    }

    if (_burnerLimits.length == _bridges.length && _burnerLimits.length != 0) {
      XERC20(_xerc20).createBurnerLimits(_burnerLimits, _bridges);
    }

    XERC20(_xerc20).setLockbox(_lockbox);
    XERC20(_xerc20).transferOwnership(msg.sender);
  }

  function _deployLockbox(address _xerc20, address _baseToken) internal returns (address _lockbox) {
    bytes32 _salt = keccak256(abi.encodePacked(_xerc20, _baseToken, msg.sender));
    bytes memory _creation = type(XERC20Lockbox).creationCode;
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_xerc20, _baseToken));

    _lockbox = CREATE3.deploy(_salt, _bytecode, 0);

    lockboxRegistryArray.push(_lockbox);
    lockboxRegistry[_xerc20] = _lockbox;
  }
}