// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract OTAuction is Ownable { 
    using SafeERC20 for IERC20;

    struct SaleInfo {
        IERC20 OT;
        address approver;
        uint256 startAt;
        uint256 endAt;
        uint256 otSupply;
        uint256 floorValue;
        uint256 capMKTValue;
        uint256 totalReceived;
    }

    struct Position {
        uint256 value;
        bool claimed;
    }

    SaleInfo public saleInfo;
    // global value
    address[] public acceptedCoin;
    mapping(address => bool) public acceptedCoinExist;
    bool public withdrawn;
    bool public allowClaim = false;
    mapping(address => uint256) public acceptedCoinBalance;
    // user value
    mapping(address => Position) public userPosition;
    mapping(address => mapping(address => uint256)) public userPositonStable;

    modifier onlyAtSaleTime() {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp > saleInfo.startAt && block.timestamp < saleInfo.endAt, "onlyAtSaleTime");
        _;
    }

    event BuyOT(
        address account,
        address token,
        uint256 tokenAmount,
        uint256 otSupply,
        uint256 floorValue,
        uint256 capMKTValue,
        uint256 totalReceived
    );

    constructor(
        address _OT,
        address _approver,
        uint256 _startAt, 
        uint256 _endAt,
        uint256 _otSupply, 
        uint256 _floorValue,
        uint256 _capMKTValue,
        address[] memory _acceptedCoin
    ) {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp < _startAt, "StartAt must future");
        require(_startAt < _endAt, "EndAt must gt StartAt");
        require(_capMKTValue >= _floorValue, "capMKTValue must gt floorValue");
        saleInfo.OT = IERC20(_OT);
        saleInfo.approver = _approver;
        saleInfo.startAt = _startAt;
        saleInfo.endAt = _endAt;
        saleInfo.otSupply = _otSupply;
        // _floorValue = usd  floorValue = usd * (10 ** 30)
        saleInfo.floorValue = _floorValue * 1e30;
        saleInfo.capMKTValue = _capMKTValue * 1e30;
        withdrawn = false;
        for (uint i = 0; i < _acceptedCoin.length; i++) {
            acceptedCoin.push(_acceptedCoin[i]);
            acceptedCoinBalance[_acceptedCoin[i]] = 0;
            acceptedCoinExist[_acceptedCoin[i]] = true;
        }
    }

    function _allowClaim() external onlyOwner{
        allowClaim = true;
    }

    function buyOT(address _address, uint256 _amount) external onlyAtSaleTime {
        require(acceptedCoinExist[_address], "Token not supported");
        IERC20(_address).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _value = _amount * (10 ** (30 - IERC20Metadata(_address).decimals()));
        userPosition[msg.sender].value += _value;
        saleInfo.totalReceived += _value;
        
        require(saleInfo.totalReceived <= saleInfo.capMKTValue, "cap is filled");
        userPositonStable[msg.sender][_address] += _amount;
        acceptedCoinBalance[_address] += _amount;
        emit BuyOT(
            msg.sender, 
            _address, 
            _amount, 
            saleInfo.otSupply, 
            saleInfo.floorValue, 
            saleInfo.capMKTValue, 
            saleInfo.totalReceived
        );
    }

    function claimOT() external {
        require(userPosition[msg.sender].value > 0, "You don't have a position");
        require(!userPosition[msg.sender].claimed, "You have already claimed");
        require(allowClaim, "Not allowed to claim");
        userPosition[msg.sender].claimed = true;
        uint256 volume;
        if (saleInfo.totalReceived > saleInfo.floorValue) {
            volume = saleInfo.totalReceived;
        } else {
            volume = saleInfo.floorValue;
        }
        uint256 boughtOTAmount = userPosition[msg.sender].value * saleInfo.otSupply / volume;
        saleInfo.OT.safeTransferFrom(saleInfo.approver, msg.sender, boughtOTAmount);
    }

    function withdrawProceeds(address to) external onlyOwner {
        require(!withdrawn, "withdrawn");
        require(block.timestamp > saleInfo.endAt || saleInfo.totalReceived == saleInfo.capMKTValue, "cap not filled");
        withdrawn = true;
        for (uint i = 0; i < acceptedCoin.length; i++) {
            IERC20(acceptedCoin[i]).transfer(to, acceptedCoinBalance[acceptedCoin[i]]);
        }
    }
    
    function getAccountInfo(address _account) external view returns (
        address OTAddress,
        uint256 otSupply,
        uint256 floorValue,
        uint256 capMKTValue,
        uint256 totalReceived,
        uint256 boughtOTAmount, 
        address[] memory tokens,
        uint256[] memory contributedAmount,
        uint256[] memory globalContributedAmount,
        uint8[] memory tokensDecimals
    ) {
        OTAddress = address(saleInfo.OT);
        otSupply = saleInfo.otSupply;
        floorValue = saleInfo.floorValue;
        capMKTValue = saleInfo.capMKTValue;
        totalReceived = saleInfo.totalReceived;
        uint256 volume;
        if (saleInfo.totalReceived > saleInfo.floorValue) {
            volume = saleInfo.totalReceived;
        } else {
            volume = saleInfo.floorValue;
        }
        boughtOTAmount = userPosition[_account].value * saleInfo.otSupply / volume;
        tokens = new address[](acceptedCoin.length);
        contributedAmount = new uint256[](acceptedCoin.length);
        globalContributedAmount = new uint256[](acceptedCoin.length);
        tokensDecimals = new uint8[](acceptedCoin.length);
        for (uint i = 0; i < acceptedCoin.length; i++) {
            address token = acceptedCoin[i];
            tokens[i] = token;
            contributedAmount[i] = userPositonStable[_account][token];
            globalContributedAmount[i] = acceptedCoinBalance[token];
            tokensDecimals[i] = IERC20Metadata(token).decimals();
        }
    }
    // to recover tokens accidentally sent to this contract
    function withdrawERC20Token(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }
}