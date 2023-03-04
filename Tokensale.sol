// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract SaleToken is Ownable { 
    using SafeERC20 for IERC20;

    struct SaleInfo {
        IERC20 saleToken;
        address approver;
        uint256 startAt;
        uint256 endAt;
        uint256 saleTokenAmount;
        uint256 marketValue;
        uint256 capMarketValue;
        uint256 saleVolume;
    }

    struct Position {
        uint256 value;
        bool isWithdraw;
    }

    SaleInfo public saleInfo;
    // global value
    address[] public supportStableCoin;
    mapping(address => bool) public supportStableCoinExist;
    bool public withdraw;
    mapping(address => uint256) public supportStableCoinSaleNumber;
    // user value
    mapping(address => Position) public userPosition;
    mapping(address => mapping(address => uint256)) public userPositonStable;

    modifier onlyAtSaleTime() {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp > saleInfo.startAt && block.timestamp < saleInfo.endAt, "onlyAtSaleTime");
        _;
    }

    modifier onlyAtEndTime(){
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp > saleInfo.endAt || saleInfo.saleVolume == saleInfo.capMarketValue, "onlyAtEndTime");
        _;
    }

    event BuyToken(
        address account,
        address token,
        uint256 tokenAmount,
        uint256 saleTokenAmount,
        uint256 marketValue,
        uint256 capMarketValue,
        uint256 saleVolume
    );

    constructor(
        address _saleToken,
        address _approver,
        uint256 _startAt, 
        uint256 _endAt,
        uint256 _saleTokenAmount, 
        uint256 _marketValue,
        uint256 _capMarketValue,
        address[] memory _supportStableCoin
    ) {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp < _startAt, "StartAt must future");
        require(_startAt < _endAt, "EndAt must gt StartAt");
        require(_capMarketValue >= _marketValue, "CapMarketValue must gt MarketValue");
        saleInfo.saleToken = IERC20(_saleToken);
        saleInfo.approver = _approver;
        saleInfo.startAt = _startAt;
        saleInfo.endAt = _endAt;
        saleInfo.saleTokenAmount = _saleTokenAmount;
        // _marketValue = usd  marketValue = usd * (10 ** 30)
        saleInfo.marketValue = _marketValue * 1e30;
        saleInfo.capMarketValue = _capMarketValue * 1e30;
        withdraw = false;
        for (uint i = 0; i < _supportStableCoin.length; i++) {
            supportStableCoin.push(_supportStableCoin[i]);
            supportStableCoinSaleNumber[_supportStableCoin[i]] = 0;
            supportStableCoinExist[_supportStableCoin[i]] = true;
        }
    }

    function setEndTime(uint256 _endAt) externa onlyOwner{
        require(saleInfo.saleVolume == saleInfo.capMarketValue, "onlyAtEndTime");
        saleInfo.endAt = _endAt;
    }

    function buyToken(address _tokenAddress, uint256 _tokenAmount) external onlyAtSaleTime {
        require(supportStableCoinExist[_tokenAddress], "Token not support");
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenAmount);
        uint256 _saleValue = _tokenAmount * (10 ** (30 - IERC20Metadata(_tokenAddress).decimals()));
        userPosition[msg.sender].value += _saleValue;
        saleInfo.saleVolume += _saleValue;
        if(saleInfo.saleVolume == saleInfo.capMarketValue){
            saleInfo.endAt = block.timestamp;
        }
        require(saleInfo.saleVolume <= saleInfo.capMarketValue, "SaleVolume must lte CapMarketValue");
        userPositonStable[msg.sender][_tokenAddress] += _tokenAmount;
        supportStableCoinSaleNumber[_tokenAddress] += _tokenAmount;
        emit BuyToken(
            msg.sender, 
            _tokenAddress, 
            _tokenAmount, 
            saleInfo.saleTokenAmount, 
            saleInfo.marketValue, 
            saleInfo.capMarketValue, 
            saleInfo.saleVolume
        );
    }

    function withdrawToken() external onlyAtEndTime {
        require(!userPosition[msg.sender].isWithdraw, "You have already withdrawn");
        userPosition[msg.sender].isWithdraw = true;
        uint256 volume;
        if (saleInfo.saleVolume > saleInfo.marketValue) {
            volume = saleInfo.saleVolume;
        } else {
            volume = saleInfo.marketValue;
        }
        uint256 userBuyTokenAmount = userPosition[msg.sender].value * saleInfo.saleTokenAmount / volume;
        saleInfo.saleToken.safeTransferFrom(saleInfo.approver, msg.sender, userBuyTokenAmount);
    }

    function settleSaleToken(address to) external onlyOwner {
        require(!withdraw, "Admin have already withdraw");
        require(block.timestamp > saleInfo.endAt || saleInfo.saleVolume == saleInfo.capMarketValue, "onlyAtEndTime");
        withdraw = true;
        for (uint i = 0; i < supportStableCoin.length; i++) {
            IERC20(supportStableCoin[i]).transfer(to, supportStableCoinSaleNumber[supportStableCoin[i]]);
        }
    }
    
    function getAccountInfo(address _account) external view returns (
        address saleTokenAddress,
        uint256 saleTokenAmount,
        uint256 marketValue,
        uint256 capMarketValue,
        uint256 saleVolume,
        uint256 userBuyTokenAmount, 
        address[] memory tokens,
        uint256[] memory tokensUserAmount,
        uint256[] memory tokensGlobalAmount,
        uint8[] memory tokensDecimals
    ) {
        saleTokenAddress = address(saleInfo.saleToken);
        saleTokenAmount = saleInfo.saleTokenAmount;
        marketValue = saleInfo.marketValue;
        capMarketValue = saleInfo.capMarketValue;
        saleVolume = saleInfo.saleVolume;
        uint256 volume;
        if (saleInfo.saleVolume > saleInfo.marketValue) {
            volume = saleInfo.saleVolume;
        } else {
            volume = saleInfo.marketValue;
        }
        userBuyTokenAmount = userPosition[_account].value * saleInfo.saleTokenAmount / volume;
        tokens = new address[](supportStableCoin.length);
        tokensUserAmount = new uint256[](supportStableCoin.length);
        tokensGlobalAmount = new uint256[](supportStableCoin.length);
        tokensDecimals = new uint8[](supportStableCoin.length);
        for (uint i = 0; i < supportStableCoin.length; i++) {
            address token = supportStableCoin[i];
            tokens[i] = token;
            tokensUserAmount[i] = userPositonStable[_account][token];
            tokensGlobalAmount[i] = supportStableCoinSaleNumber[token];
            tokensDecimals[i] = IERC20Metadata(token).decimals();
        }
    }
    // to help users who accidentally send their tokens to this contract
    function withdrawERC20Token(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }
}