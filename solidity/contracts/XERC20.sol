// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {IXERC20} from 'interfaces/IXERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

contract XERC20 is ERC20, Ownable, IXERC20, ERC20Permit {
  using EnumerableSet for EnumerableSet.AddressSet;

  /**
   * @notice The duration it takes for the limits to fully replenish
   */
  uint256 private constant _DURATION = 1 days;

  /**
   * @notice The address of the factory which deployed this contract
   */
  address public immutable FACTORY;

  /**
   * @notice The address of the lockbox contract
   */
  address public lockbox;

  /**
   * @notice The set of whitelisted minters
   */
  EnumerableSet.AddressSet internal _mintersSet;

  /**
   * @notice The set of whitelisted burners
   */
  EnumerableSet.AddressSet internal _burnersSet;

  /**
   * @notice The address that maps to the parameters for a minter
   */
  mapping(address => Parameters) public minterParams;

  /**
   * @notice The address that maps to the parameters for a burner
   */
  mapping(address => Parameters) public burnerParams;

  /**
   * @notice Constructs the initial config of the XERC20
   *
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _factory The factory which deployed this contract
   */

  constructor(
    string memory _name,
    string memory _symbol,
    address _factory
  ) ERC20(string.concat('x', _name), string.concat('x', _symbol)) ERC20Permit(string.concat('x', _name)) {
    _transferOwnership(_factory);
    FACTORY = _factory;
  }

  /**
   * @notice Mints tokens for a user
   * @dev Can only be called by a minter
   * @param _user The address of the user who needs tokens minted
   * @param _amount The amount of tokens being minted
   */

  function mint(address _user, uint256 _amount) public {
    _mintWithCaller(msg.sender, _user, _amount);
  }

  /**
   * @notice Burns tokens for a user
   * @dev Can only be called by a burner
   * @param _user The address of the user who needs tokens burned
   * @param _amount The amount of tokens being burned
   */

  function burn(address _user, uint256 _amount) public {
    _burnWithCaller(msg.sender, _user, _amount);
  }
  /**
   * @notice Overrides transfer to call burn/mint based on the recipient
   * @dev Some bridges transfer instead of minting/burning. In that case, if you transfer tokens to a bridge we burn them and if the bridge transfers tokens we mint for the recipient, if neither apply we will just call the ERC20 transfer
   * @param _to The address of the recipient
   * @param _amount The amount of tokens to transfer
   */

  function transfer(address _to, uint256 _amount) public override returns (bool _result) {
    bool _minterStatus = minterParams[msg.sender].isBridge;
    bool _burnerStatus = burnerParams[_to].isBridge;

    if (_minterStatus && _burnerStatus) {
      _mintWithCaller(msg.sender, msg.sender, _amount);
      _burnWithCaller(_to, msg.sender, _amount);
      _result = true;
    } else {
      if (_minterStatus) {
        _mintWithCaller(msg.sender, _to, _amount);
        _result = true;
      }

      if (_burnerStatus) {
        _burnWithCaller(_to, msg.sender, _amount);
        _result = true;
      }
    }

    if (!_result) _result = super.transfer(_to, _amount);
  }

  /**
   * _
   * @notice Overrides transfer to call burn/mint based on the recipient
   * @dev Some bridges transfer instead of minting/burning. In that case, if you transfer tokens to a bridge we burn them and if the bridge transfers tokens we mint for the recipient, if neither apply we will just call the ERC20 transferFrom
   * @param _from The address of the sender
   * @param _to The address of the recipient
   * @param _amount The amount of tokens to transfer
   */

  function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool _result) {
    bool _minterStatus = minterParams[_from].isBridge;
    bool _burnerStatus = burnerParams[_to].isBridge;

    if (_minterStatus && _burnerStatus) {
      _mintWithCaller(msg.sender, msg.sender, _amount);
      _burnWithCaller(_to, msg.sender, _amount);

      _result = true;
    } else {
      if (_minterStatus) {
        _spendAllowance(_from, msg.sender, _amount);

        _mintWithCaller(_from, _to, _amount);
        _result = true;
      }

      if (_burnerStatus) {
        _spendAllowance(_from, msg.sender, _amount);

        _burnWithCaller(_to, _from, _amount);
        _result = true;
      }
    }

    if (!_result) _result = super.transferFrom(_from, _to, _amount);
  }

  /**
   * @notice Sets the lockbox address
   *
   * @param _lockbox The address of the lockbox
   */

  function setLockbox(address _lockbox) public {
    if (msg.sender != FACTORY) revert IXERC20_NotFactory();
    lockbox = _lockbox;

    emit LockboxSet(_lockbox);
  }

  /**
   * @notice Creates limits for minters
   * @dev _limits and _minters are parallel arrays and should be the same length
   * @param _limits The limits to be added to the minters
   * @param _minters The minters who will recieve the limits
   */

  function createMinterLimits(uint256[] memory _limits, address[] memory _minters) external onlyOwner {
    uint256 _mintersLength = _minters.length;
    if (_limits.length != _mintersLength) revert IXERC20_IncompatibleLengths();

    for (uint256 _i; _i < _mintersLength;) {
      _changeMinterLimit(_limits[_i], _minters[_i]);
      unchecked {
        ++_i;
      }
    }
  }

  /**
   * @notice Creates limits for burners
   * @dev _limits and _minters are parallel arrays and should be the same length
   * @param _limits The limits to be added to the minters
   * @param _burners The minters who will recieve the limits
   */

  function createBurnerLimits(uint256[] memory _limits, address[] memory _burners) external onlyOwner {
    uint256 _burnersLength = _burners.length;
    if (_limits.length != _burnersLength) revert IXERC20_IncompatibleLengths();

    for (uint256 _i; _i < _burnersLength;) {
      _changeBurnerLimit(_limits[_i], _burners[_i]);

      unchecked {
        ++_i;
      }
    }
  }

  /**
   * @notice Updates the limit of any minter
   * @dev Can only be called by the owner
   * @param _limit The updated limit we are setting to the minter
   * @param _minter The address of the minter we are setting the limit too
   */

  function changeMinterLimit(uint256 _limit, address _minter) external onlyOwner {
    _changeMinterLimit(_limit, _minter);
  }

  /**
   * @notice Updates the limit of any burner
   * @dev Can only be called by the owner
   * @param _limit The updated limit we are setting to the minter
   * @param _burner The address of the burner we are setting the limit too
   */

  function changeBurnerLimit(uint256 _limit, address _burner) external onlyOwner {
    _changeBurnerLimit(_limit, _burner);
  }

  /**
   * @notice Removes a minter
   * @dev Can only be called by the owner
   * @param _minter The minter we are removing
   */

  function removeMinter(address _minter) external onlyOwner {
    delete minterParams[_minter];
  }

  /**
   * @notice Removes a burner
   * @dev Can only be called by the owner
   * @param _burner The burner we are removing
   */

  function removeBurner(address _burner) external onlyOwner {
    delete burnerParams[_burner];
  }

  /**
   * @notice Returns the max limit of a minter
   *
   * @param _minter The minter we are viewing the limits of
   * @return _limit The limit the minter has
   */

  function getMinterMaxLimit(address _minter) public view returns (uint256 _limit) {
    _limit = minterParams[_minter].maxLimit;
  }

  /**
   * @notice Returns the max limit of a burner
   *
   * @param _burner The burner we are viewing the limits of
   * @return _limit The limit the burner has
   */

  function getBurnerMaxLimit(address _burner) public view returns (uint256 _limit) {
    _limit = burnerParams[_burner].maxLimit;
  }

  /**
   * @notice Returns the current limit of a minter
   *
   * @param _minter The minter we are viewing the limits of
   * @return _limit The limit the minter has
   */

  function getMinterCurrentLimit(address _minter) public view returns (uint256 _limit) {
    _limit = _getCurrentLimit(
      minterParams[_minter].currentLimit,
      minterParams[_minter].maxLimit,
      minterParams[_minter].timestamp,
      minterParams[_minter].ratePerSecond
    );
  }

  /**
   * @notice Returns the current limit of a burner
   *
   * @param _burner The burner we are viewing the limits of
   * @return _limit The limit the minter has
   */

  function getBurnerCurrentLimit(address _burner) public view returns (uint256 _limit) {
    _limit = _getCurrentLimit(
      burnerParams[_burner].currentLimit,
      burnerParams[_burner].maxLimit,
      burnerParams[_burner].timestamp,
      burnerParams[_burner].ratePerSecond
    );
  }

  /**
   * @notice Loops through the array of minters
   *
   * @param _start The start of the loop
   * @param _amount The amount of minters to loop through
   * @return _minters The array of minters from the start to start + amount
   */

  function getMinters(uint256 _start, uint256 _amount) external view returns (address[] memory _minters) {
    uint256 _mintersLength = EnumerableSet.length(_mintersSet);
    if (_amount > _mintersLength - _start) {
      _amount = _mintersLength - _start;
    }

    _minters = new address[](_amount);
    uint256 _index;
    while (_index < _amount) {
      _minters[_index] = EnumerableSet.at(_mintersSet, _start + _index);

      unchecked {
        ++_index;
      }
    }
  }

  /**
   * @notice Loops through the array of burners
   *
   * @param _start The start of the loop
   * @param _amount The amount of burners to loop through
   * @return _burners The array of burners from the start to start + amount
   */

  function getBurners(uint256 _start, uint256 _amount) public view returns (address[] memory _burners) {
    uint256 _burnersLength = EnumerableSet.length(_burnersSet);
    if (_amount > _burnersLength - _start) {
      _amount = _burnersLength - _start;
    }

    _burners = new address[](_amount);
    uint256 _index;
    while (_index < _amount) {
      _burners[_index] = EnumerableSet.at(_burnersSet, _start + _index);

      unchecked {
        ++_index;
      }
    }
  }

  /**
   * @notice Uses the limit of any minter
   * @param _change The change in the limit
   * @param _minter The address of the minter who is being changed
   */

  function _useMinterLimits(uint256 _change, address _minter) internal {
    uint256 _currentLimit = getMinterCurrentLimit(_minter);
    minterParams[_minter].timestamp = block.timestamp;
    minterParams[_minter].currentLimit = _currentLimit - _change;
  }

  /**
   * @notice Uses the limit of any burner
   * @param _change The change in the limit
   * @param _burner The address of the burner who is being changed
   */

  function _useBurnerLimits(uint256 _change, address _burner) internal {
    uint256 _currentLimit = getBurnerCurrentLimit(_burner);
    burnerParams[_burner].timestamp = block.timestamp;
    burnerParams[_burner].currentLimit = _currentLimit - _change;
  }

  /**
   * @notice Updates the limit of any minter
   * @dev Can only be called by the owner
   * @param _limit The updated limit we are setting to the minter
   * @param _minter The address of the minter we are setting the limit too
   */

  function _changeMinterLimit(uint256 _limit, address _minter) internal {
    uint256 _oldLimit = minterParams[_minter].maxLimit;
    uint256 _currentLimit = getMinterCurrentLimit(_minter);
    minterParams[_minter].maxLimit = _limit;

    if (_limit != 0 && !minterParams[_minter].isBridge) {
      minterParams[_minter].isBridge = true;
      EnumerableSet.add(_mintersSet, _minter);
    }

    minterParams[_minter].currentLimit = _calculateNewCurrentLimit(_limit, _oldLimit, _currentLimit);

    minterParams[_minter].ratePerSecond = _limit / _DURATION;
    minterParams[_minter].timestamp = block.timestamp;
    emit MinterLimitsSet(_limit, _minter);
  }

  /**
   * @notice Updates the limit of any burner
   * @dev Can only be called by the owner
   * @param _limit The updated limit we are setting to the minter
   * @param _burner The address of the burner we are setting the limit too
   */

  function _changeBurnerLimit(uint256 _limit, address _burner) internal {
    uint256 _oldLimit = burnerParams[_burner].maxLimit;
    uint256 _currentLimit = getBurnerCurrentLimit(_burner);
    burnerParams[_burner].maxLimit = _limit;

    if (_limit != 0 && !burnerParams[_burner].isBridge) {
      burnerParams[_burner].isBridge = true;
      EnumerableSet.add(_burnersSet, _burner);
    }

    burnerParams[_burner].currentLimit = _calculateNewCurrentLimit(_limit, _oldLimit, _currentLimit);

    burnerParams[_burner].ratePerSecond = _limit / _DURATION;
    burnerParams[_burner].timestamp = block.timestamp;
    emit BurnerLimitsSet(_limit, _burner);
  }

  /**
   * @notice Updates the current limit
   *
   * @param _limit The new limit
   * @param _oldLimit The old limit
   * @param _currentLimit The current limit
   */

  function _calculateNewCurrentLimit(
    uint256 _limit,
    uint256 _oldLimit,
    uint256 _currentLimit
  ) internal pure returns (uint256 _newCurrentLimit) {
    uint256 _difference;

    if (_oldLimit > _limit) {
      _difference = _oldLimit - _limit;
      _newCurrentLimit = _currentLimit > _difference ? _currentLimit - _difference : 0;
    } else {
      _difference = _limit - _oldLimit;
      _newCurrentLimit = _currentLimit + _difference;
    }
  }

  /**
   * @notice Gets the current limit
   *
   * @param _currentLimit The current limit
   * @param _maxLimit The max limit
   * @param _timestamp The timestamp of the last update
   * @param _ratePerSecond The rate per second
   */

  function _getCurrentLimit(
    uint256 _currentLimit,
    uint256 _maxLimit,
    uint256 _timestamp,
    uint256 _ratePerSecond
  ) internal view returns (uint256 _limit) {
    _limit = _currentLimit;
    if (_limit == _maxLimit) {
      return _limit;
    } else if (_timestamp + _DURATION <= block.timestamp) {
      _limit = _maxLimit;
    } else if (_timestamp + _DURATION > block.timestamp) {
      uint256 _timePassed = block.timestamp - _timestamp;
      uint256 _calculatedLimit = _limit + (_timePassed * _ratePerSecond);
      _limit = _calculatedLimit > _maxLimit ? _maxLimit : _calculatedLimit;
    }
  }

  /**
   * @notice Internal function for burning tokens
   *
   * @param _caller The caller address
   * @param _user The user address
   * @param _amount The amount to burn
   */

  function _burnWithCaller(address _caller, address _user, uint256 _amount) internal {
    if (_caller != lockbox) {
      uint256 _currentLimit = getBurnerCurrentLimit(_caller);
      if (_currentLimit < _amount) revert IXERC20_NotHighEnoughLimits();
      _useBurnerLimits(_amount, _caller);
    }
    _burn(_user, _amount);
  }

  /**
   * @notice Internal function for minting tokens
   *
   * @param _caller The caller address
   * @param _user The user address
   * @param _amount The amount to mint
   */

  function _mintWithCaller(address _caller, address _user, uint256 _amount) internal {
    if (_caller != lockbox) {
      uint256 _currentLimit = getMinterCurrentLimit(_caller);
      if (_currentLimit < _amount) revert IXERC20_NotHighEnoughLimits();
      _useMinterLimits(_amount, _caller);
    }
    _mint(_user, _amount);
  }
}
