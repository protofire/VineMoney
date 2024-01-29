// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPriceFeed {
    event NewOracleRegistered(address token, address bandAggregator);
    event PriceFeedStatusUpdated(address token, address oracle, bool isWorking);
    event PriceRecordUpdated(address indexed token, uint256 _price);

    function fetchPrice(address _token) external returns (uint256);

    function loadPrice(address _token) external view returns (uint256);

    function setOracle(
        address _token,
        address _bandOracle,
        string memory _base,
        string memory _quote,
        uint32 _heartbeat
    ) external;

    function MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND() external view returns (uint256);

    function VINE_CORE() external view returns (address);

    function RESPONSE_TIMEOUT() external view returns (uint256);

    function guardian() external view returns (address);

    function oracleRecords(
        address
    )
        external
        view
        returns (
            address bandOracle,
            string memory base,
            string memory quote,
            uint32 heartbeat,
            bool isFeedWorking
        );

    function owner() external view returns (address);

    function priceRecords(
        address
    ) external view returns (uint96 price, uint32 timestamp, uint32 lastUpdated);
}
