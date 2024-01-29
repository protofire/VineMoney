// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import "../interfaces/IStdReference.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../dependencies/VineMath.sol";
import "../dependencies/VineOwnable.sol";

/**
    @title Vine Multi Token Price Feed
    @notice Based on Gravita's PriceFeed:
            https://github.com/Gravita-Protocol/Gravita-SmartContracts/blob/9b69d555f3567622b0f84df8c7f1bb5cd9323573/contracts/PriceFeed.sol

            Vine's implementation additionally caches price values within a block and incorporates exchange rate settings for derivative tokens (e.g. stETH -> wstETH).
 */
contract PriceFeed is VineOwnable {
    struct OracleRecord {
        IStdReference bandOracle;
        string base;
        string quote;
        uint32 heartbeat;
        bool isFeedWorking;
    }

    struct PriceRecord {
        uint96 price;
        uint32 timestamp;
        uint32 lastUpdated;
    }

    struct FeedResponse {
        uint256 rate;
        uint256 lastUpdatedBase;
        uint256 lastUpdatedQuote;
        bool success;
    }

    // Custom Errors --------------------------------------------------------------------------------------------------

    error PriceFeed__InvalidFeedResponseError(address token);
    error PriceFeed__FeedFrozenError(address token);
    error PriceFeed__UnknownFeedError(address token);
    error PriceFeed__HeartbeatOutOfBoundsError();

    // Events ---------------------------------------------------------------------------------------------------------

    event NewOracleRegistered(address token, address bandAggregator);
    event PriceFeedStatusUpdated(address token, address oracle, bool isWorking);
    event PriceRecordUpdated(address indexed token, uint256 _price);

    /** Constants ---------------------------------------------------------------------------------------------------- */

    // Responses are considered stale this many seconds after the oracle's heartbeat
    uint256 public constant RESPONSE_TIMEOUT_BUFFER = 1 hours;

    // Maximum deviation allowed between two consecutive Band oracle prices. 18-digit precision.
    uint256 public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

    // State ------------------------------------------------------------------------------------------------------------

    mapping(address => OracleRecord) public oracleRecords;
    mapping(address => PriceRecord) public priceRecords;

    struct OracleSetup {
        address token;
        address band;
        string base;
        string quote;
        uint32 heartbeat;
    }

    constructor(address _vineCore, OracleSetup[] memory oracles) VineOwnable(_vineCore) {
        for (uint i = 0; i < oracles.length; i++) {
            OracleSetup memory o = oracles[i];
            _setOracle(o.token, o.band, o.base, o.quote, o.heartbeat);
        }
    }

    // Admin routines ---------------------------------------------------------------------------------------------------

    /**
        @notice Set the oracle for a specific token
        @param _token Address of the LST to set the oracle for
        @param _bandOracle Address of the band oracle for this LST
        @param _base The base symbol as type string
        @param _quote The quote symbol as type string
        @param _heartbeat Oracle heartbeat, in seconds
     */
    function setOracle(
        address _token,
        address _bandOracle,
        string memory _base,
        string memory _quote,
        uint32 _heartbeat
    ) external onlyOwner {
        _setOracle(_token, _bandOracle, _base, _quote, _heartbeat);
    }

    function _setOracle(
        address _token,
        address _bandOracle,
        string memory _base,
        string memory _quote,
        uint32 _heartbeat
    ) internal {
        if (_heartbeat > 86400) revert PriceFeed__HeartbeatOutOfBoundsError();
        IStdReference newFeed = IStdReference(_bandOracle);
        

        OracleRecord memory record = OracleRecord({
            bandOracle: newFeed,
            base: _base,
            quote: _quote,
            heartbeat: _heartbeat,
            isFeedWorking: true
        });

        FeedResponse memory currResponse = _fetchCurrentFeedResponse(record);

        if (!_isFeedWorking(currResponse, _heartbeat)) {
            revert PriceFeed__InvalidFeedResponseError(_token);
        }

        oracleRecords[_token] = record;
        // _processFeedResponses(_token, record, currResponse, _priceRecord);
        _storePrice(_token, currResponse.rate, currResponse.lastUpdatedBase);
        emit NewOracleRegistered(_token, _bandOracle);
    }

    // Public functions -------------------------------------------------------------------------------------------------

    /**
        @notice Get the latest price returned from the oracle
        @dev You can obtain these values by calling `TroveManager.fetchPrice()`
             rather than directly interacting with this contract.
        @param _token Token to fetch the price for
        @return The latest valid price for the requested token
     */
    function fetchPrice(address _token) public returns (uint256) {
        PriceRecord memory priceRecord = priceRecords[_token];
        OracleRecord memory oracle = oracleRecords[_token];

        uint256 price = priceRecord.price;
        // We short-circuit only if the price was already correct in the current block
        if (priceRecord.lastUpdated != block.timestamp) {
            if (priceRecord.lastUpdated == 0) {
                revert PriceFeed__UnknownFeedError(_token);
            }

            FeedResponse memory currResponse = _fetchCurrentFeedResponse(
                oracle
            );

            if (!_isFeedWorking(currResponse, oracle.heartbeat)) {
                revert PriceFeed__InvalidFeedResponseError(_token);
            } else {
                price = _processFeedResponses(_token, oracle, currResponse, priceRecord);
                priceRecord.lastUpdated = uint32(block.timestamp);
                priceRecords[_token] = priceRecord;
            }
        }

        return price;
    }

    function loadPrice(address _token) public view returns(uint256) {
        OracleRecord memory oracle = oracleRecords[_token];
        FeedResponse memory currResponse = _fetchCurrentFeedResponse(oracle);
        return currResponse.rate;
    }

    // Internal functions -----------------------------------------------------------------------------------------------

    function _processFeedResponses(
        address _token,
        OracleRecord memory oracle,
        FeedResponse memory _currResponse,
        PriceRecord memory priceRecord
    ) internal returns (uint256) {
        bool isValidResponse = _isFeedWorking(_currResponse, oracle.heartbeat) &&
            !_isPriceChangeAboveMaxDeviation(_currResponse, priceRecord);
        if (isValidResponse) {
            uint256 price = uint256(_currResponse.rate);
            if (!oracle.isFeedWorking) {
                _updateFeedStatus(_token, oracle, true);
            }
            _storePrice(_token, price, _currResponse.lastUpdatedBase);
            return price;
        } else {
            if (oracle.isFeedWorking) {
                _updateFeedStatus(_token, oracle, false);
            }
            if (_isPriceStale(priceRecord.timestamp, oracle.heartbeat)) {
                revert PriceFeed__FeedFrozenError(_token);
            }
            return priceRecord.price;
        }
    }

    function _isPriceStale(uint256 _priceTimestamp, uint256 _heartbeat) internal view returns (bool) {
        return _priceTimestamp > 0 && block.timestamp - _priceTimestamp > _heartbeat + RESPONSE_TIMEOUT_BUFFER;
    }

    function _isFeedWorking(
        FeedResponse memory _currentResponse,
        uint256 _heartbeat
    ) internal view returns (bool) {
        return _currentResponse.success == true && _isValidResponse(_currentResponse) && !_isPriceStale(_currentResponse.lastUpdatedBase, _heartbeat) && !_isPriceStale(_currentResponse.lastUpdatedQuote, _heartbeat);
    }

    function _isValidResponse(FeedResponse memory _response) internal view returns (bool) {
        return
            (_response.rate != 0) &&
            (_response.lastUpdatedBase != 0) &&
            (_response.lastUpdatedBase <= block.timestamp) &&
            (_response.lastUpdatedQuote != 0) &&
            (_response.lastUpdatedQuote <= block.timestamp);
    }

    function _isPriceChangeAboveMaxDeviation(
        FeedResponse memory _currResponse,
        PriceRecord memory priceRecord
    ) internal pure returns (bool) {
        uint256 currentPrice = uint256(_currResponse.rate);
        uint256 prevPrice = uint256(priceRecord.price);

        uint256 minPrice = VineMath._min(currentPrice, prevPrice);
        uint256 maxPrice = VineMath._max(currentPrice, prevPrice);

        /*
         * Use the larger price as the denominator:
         * - If price decreased, the percentage deviation is in relation to the previous price.
         * - If price increased, the percentage deviation is in relation to the current price.
         */
        uint256 percentDeviation = ((maxPrice - minPrice) * VineMath.DECIMAL_PRECISION) / maxPrice;

        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }

    function _updateFeedStatus(address _token, OracleRecord memory _oracle, bool _isWorking) internal {
        oracleRecords[_token].isFeedWorking = _isWorking;
        emit PriceFeedStatusUpdated(_token, address(_oracle.bandOracle), _isWorking);
    }

    function _storePrice(address _token, uint256 _price, uint256 _timestamp) internal {
        priceRecords[_token] = PriceRecord({
            price: uint96(_price),
            timestamp: uint32(_timestamp),
            lastUpdated: uint32(block.timestamp)
        });
        emit PriceRecordUpdated(_token, _price);
    }

    function _fetchCurrentFeedResponse(
        OracleRecord memory _oracle
    ) internal view returns (FeedResponse memory response) {
        IStdReference _priceAggregator = IStdReference(_oracle.bandOracle);
        try _priceAggregator.getReferenceData(_oracle.base, _oracle.quote) returns (
            IStdReference.ReferenceData memory data) {
            response.rate = data.rate;
            response.lastUpdatedBase = data.lastUpdatedBase;
            response.lastUpdatedQuote = data.lastUpdatedQuote;
            response.success = true;
        } catch {
            // If call to Band aggregator reverts, return a zero response with success = false
            return response;
        }
    }
}
