/// SPDX-License-Identifier: Apache-2.0
/// This contract is a derivative work of the open-source work of Oasis DEX: https://github.com/OasisDEX/oasis

/// @title RubiconMarket.sol
/// @notice Please see the repository for this code at https://github.com/RubiconDeFi/rubicon-protocol-v1;

pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice DSAuth events for authentication schema
contract DSAuthEvents {
    event LogSetAuthority(address indexed authority);
    event LogSetOwner(address indexed owner);
}

/// @notice DSAuth library for setting owner of the contract
/// @dev Provides the auth modifier for authenticated function calls
contract DSAuth is DSAuthEvents {
    address public owner;

    function setOwner(address owner_) external auth {
        owner = owner_;
        emit LogSetOwner(owner);
    }

    modifier auth() {
        require(isAuthorized(msg.sender), "ds-auth-unauthorized");
        _;
    }

    function isAuthorized(address src) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else {
            return false;
        }
    }
}

/// @notice DSMath library for safe math without integer overflow/underflow
contract DSMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x >= y ? x : y;
    }

    function imin(int256 x, int256 y) internal pure returns (int256 z) {
        return x <= y ? x : y;
    }

    function imax(int256 x, int256 y) internal pure returns (int256 z) {
        return x >= y ? x : y;
    }

    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, RAY), y / 2) / y;
    }
}

// /// @notice ERC-20 interface as derived from EIP-20
// contract ERC20 {
//     function totalSupply() public view returns (uint256);

//     function balanceOf(address guy) public view returns (uint256);

//     function allowance(address src, address guy) public view returns (uint256);

//     function approve(address guy, uint256 wad) public returns (bool);

//     function transfer(address dst, uint256 wad) public returns (bool);

//     function transferFrom(
//         address src,
//         address dst,
//         uint256 wad
//     ) public returns (bool);
// }

/// @notice Events contract for logging trade activity on Rubicon Market
/// @dev Provides the key event logs that are used in all core functionality of exchanging on the Rubicon Market
contract EventfulMarket {
    event LogItemUpdate(uint256 id);
    event LogTrade(
        uint256 pay_amt,
        address indexed pay_gem,
        uint256 buy_amt,
        address indexed buy_gem
    );

    event LogMake(
        bytes32 indexed id,
        bytes32 indexed pair,
        address indexed maker,
        ERC20 pay_gem,
        ERC20 buy_gem,
        uint128 pay_amt,
        uint128 buy_amt,
        uint64 timestamp
    );

    event LogBump(
        bytes32 indexed id,
        bytes32 indexed pair,
        address indexed maker,
        ERC20 pay_gem,
        ERC20 buy_gem,
        uint128 pay_amt,
        uint128 buy_amt,
        uint64 timestamp
    );

    event LogTake(
        bytes32 id,
        bytes32 indexed pair,
        address indexed maker,
        ERC20 pay_gem,
        ERC20 buy_gem,
        address indexed taker,
        uint128 take_amt,
        uint128 give_amt,
        uint64 timestamp
    );

    event LogKill(
        bytes32 indexed id,
        bytes32 indexed pair,
        address indexed maker,
        ERC20 pay_gem,
        ERC20 buy_gem,
        uint128 pay_amt,
        uint128 buy_amt,
        uint64 timestamp
    );

    event LogInt(string lol, uint256 input);

    event FeeTake(
        bytes32 indexed id,
        bytes32 indexed pair,
        ERC20 asset,
        address indexed taker,
        address feeTo,
        uint256 feeAmt,
        uint64 timestamp
    );

    event OfferDeleted(uint256 id);
}

/// @notice Core trading logic for ERC-20 pairs, an orderbook, and transacting of tokens
/// @dev This contract holds the core ERC-20 / ERC-20 offer, buy, and cancel logic
contract SimpleMarket is EventfulMarket, DSMath {
    uint256 public last_offer_id;

    /// @dev The mapping that makes up the core orderbook of the exchange
    mapping(uint256 => OfferInfo) public offers;

    bool locked;

    /// @dev This parameter is in basis points
    uint256 internal feeBPS;

    /// @dev This parameter provides the address to which fees are sent
    address internal feeTo;

    struct OfferInfo {
        uint256 pay_amt;
        ERC20 pay_gem;
        uint256 buy_amt;
        ERC20 buy_gem;
        address owner;
        uint64 timestamp;
    }

    /// @notice Modifier that insures an order exists and is properly in the orderbook
    modifier can_buy(uint256 id) virtual {
        require(isActive(id));
        _;
    }

    /// @notice Modifier that checks the user to make sure they own the offer and its valid before they attempt to cancel it
    modifier can_cancel(uint256 id) virtual {
        require(isActive(id));
        require(getOwner(id) == msg.sender);
        _;
    }

    modifier can_offer() virtual {
        _;
    }

    modifier synchronized() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    function isActive(uint256 id) public view returns (bool active) {
        return offers[id].timestamp > 0;
    }

    function getOwner(uint256 id) public view returns (address owner) {
        return offers[id].owner;
    }

    function getOffer(uint256 id)
        public
        view
        returns (
            uint256,
            ERC20,
            uint256,
            ERC20
        )
    {
        OfferInfo memory _offer = offers[id];
        return (_offer.pay_amt, _offer.pay_gem, _offer.buy_amt, _offer.buy_gem);
    }

    /// @notice Below are the main public entrypoints

    function bump(bytes32 id_) external can_buy(uint256(id_)) {
        uint256 id = uint256(id_);
        emit LogBump(
            id_,
            keccak256(abi.encodePacked(offers[id].pay_gem, offers[id].buy_gem)),
            offers[id].owner,
            offers[id].pay_gem,
            offers[id].buy_gem,
            uint128(offers[id].pay_amt),
            uint128(offers[id].buy_amt),
            offers[id].timestamp
        );
    }

    /// @notice Accept a given `quantity` of an offer. Transfers funds from caller/taker to offer maker, and from market to caller/taker.
    /// @notice The fee for taker trades is paid in this function.
    function buy(uint256 id, uint256 quantity)
        public
        virtual
        can_buy(id)
        synchronized
        returns (bool)
    {
        OfferInfo memory _offer = offers[id];
        uint256 spend = mul(quantity, _offer.buy_amt) / _offer.pay_amt;

        require(uint128(spend) == spend, "spend is not an int");
        require(uint128(quantity) == quantity, "quantity is not an int");

        ///@dev For backwards semantic compatibility.
        if (
            quantity == 0 ||
            spend == 0 ||
            quantity > _offer.pay_amt ||
            spend > _offer.buy_amt
        ) {
            return false;
        }

        // Fee logic added on taker trades
        uint256 fee = mul(spend, feeBPS) / 10000;
        require(
            _offer.buy_gem.transferFrom(msg.sender, feeTo, fee),
            "Insufficient funds to cover fee"
        );

        offers[id].pay_amt = sub(_offer.pay_amt, quantity);
        offers[id].buy_amt = sub(_offer.buy_amt, spend);
        require(
            _offer.buy_gem.transferFrom(msg.sender, _offer.owner, spend),
            "_offer.buy_gem.transferFrom(msg.sender, _offer.owner, spend) failed - check that you can pay the fee"
        );
        require(
            _offer.pay_gem.transfer(msg.sender, quantity),
            "_offer.pay_gem.transfer(msg.sender, quantity) failed"
        );

        emit LogItemUpdate(id);
        emit LogTake(
            bytes32(id),
            keccak256(abi.encodePacked(_offer.pay_gem, _offer.buy_gem)),
            _offer.owner,
            _offer.pay_gem,
            _offer.buy_gem,
            msg.sender,
            uint128(quantity),
            uint128(spend),
            uint64(block.timestamp)
        );
        emit FeeTake(
            bytes32(id),
            keccak256(abi.encodePacked(_offer.pay_gem, _offer.buy_gem)),
            _offer.buy_gem,
            msg.sender,
            feeTo,
            fee,
            uint64(block.timestamp)
        );
        emit LogTrade(
            quantity,
            address(_offer.pay_gem),
            spend,
            address(_offer.buy_gem)
        );

        if (offers[id].pay_amt == 0) {
            delete offers[id];
            emit OfferDeleted(id);
        }

        return true;
    }

    /// @notice Allows the caller to cancel the offer if it is their own.
    /// @notice This function refunds the offer to the maker.
    function cancel(uint256 id)
        public
        virtual
        can_cancel(id)
        synchronized
        returns (bool success)
    {
        OfferInfo memory _offer = offers[id];
        delete offers[id];

        require(_offer.pay_gem.transfer(_offer.owner, _offer.pay_amt));

        emit LogItemUpdate(id);
        emit LogKill(
            bytes32(id),
            keccak256(abi.encodePacked(_offer.pay_gem, _offer.buy_gem)),
            _offer.owner,
            _offer.pay_gem,
            _offer.buy_gem,
            uint128(_offer.pay_amt),
            uint128(_offer.buy_amt),
            uint64(block.timestamp)
        );

        success = true;
    }

    function kill(bytes32 id) external virtual {
        require(cancel(uint256(id)));
    }

    function make(
        ERC20 pay_gem,
        ERC20 buy_gem,
        uint128 pay_amt,
        uint128 buy_amt
    ) external virtual returns (bytes32 id) {
        return bytes32(offer(pay_amt, pay_gem, buy_amt, buy_gem));
    }

    /// @notice Key function to make a new offer. Takes funds from the caller into market escrow.
    function offer(
        uint256 pay_amt,
        ERC20 pay_gem,
        uint256 buy_amt,
        ERC20 buy_gem
    ) public virtual can_offer synchronized returns (uint256 id) {
        require(uint128(pay_amt) == pay_amt);
        require(uint128(buy_amt) == buy_amt);
        require(pay_amt > 0);
        require(pay_gem != ERC20(0x0));
        require(buy_amt > 0);
        require(buy_gem != ERC20(0x0));
        require(pay_gem != buy_gem);

        OfferInfo memory info;
        info.pay_amt = pay_amt;
        info.pay_gem = pay_gem;
        info.buy_amt = buy_amt;
        info.buy_gem = buy_gem;
        info.owner = msg.sender;
        info.timestamp = uint64(block.timestamp);
        id = _next_id();
        offers[id] = info;

        require(pay_gem.transferFrom(msg.sender, address(this), pay_amt));

        emit LogItemUpdate(id);
        emit LogMake(
            bytes32(id),
            keccak256(abi.encodePacked(pay_gem, buy_gem)),
            msg.sender,
            pay_gem,
            buy_gem,
            uint128(pay_amt),
            uint128(buy_amt),
            uint64(block.timestamp)
        );
    }

    function take(bytes32 id, uint128 maxTakeAmount) external virtual {
        require(buy(uint256(id), maxTakeAmount));
    }

    function _next_id() internal returns (uint256) {
        last_offer_id++;
        return last_offer_id;
    }

    // Fee logic
    function getFeeBPS() internal view returns (uint256) {
        return feeBPS;
    }
}

/// @notice Expiring market is a Simple Market with a market lifetime.
/// @dev When the close_time has been reached, offers can only be cancelled (offer and buy will throw).
contract ExpiringMarket is DSAuth, SimpleMarket {
    bool public stopped;

    /// @dev After close_time has been reached, no new offers are allowed.
    modifier can_offer() override {
        require(!isClosed());
        _;
    }

    /// @dev After close, no new buys are allowed.
    modifier can_buy(uint256 id) override {
        require(isActive(id));
        require(!isClosed());
        _;
    }

    /// @dev After close, anyone can cancel an offer.
    modifier can_cancel(uint256 id) virtual override {
        require(isActive(id));
        require((msg.sender == getOwner(id)) || isClosed());
        _;
    }

    function isClosed() public pure returns (bool closed) {
        return false;
    }

    function getTime() public view returns (uint64) {
        return uint64(block.timestamp);
    }

    function stop() external auth {
        stopped = true;
    }
}

contract DSNote {
    event LogNote(
        bytes4 indexed sig,
        address indexed guy,
        bytes32 indexed foo,
        bytes32 indexed bar,
        uint256 wad,
        bytes fax
    ) anonymous;

    modifier note() {
        bytes32 foo;
        bytes32 bar;
        uint256 wad;

        assembly {
            foo := calldataload(4)
            bar := calldataload(36)
            wad := callvalue()
        }

        emit LogNote(msg.sig, msg.sender, foo, bar, wad, msg.data);

        _;
    }
}

contract MatchingEvents {
    event LogBuyEnabled(bool isEnabled);
    event LogMinSell(address pay_gem, uint256 min_amount);
    event LogMatchingEnabled(bool isEnabled);
    event LogUnsortedOffer(uint256 id);
    event LogSortedOffer(uint256 id);
    event LogInsert(address keeper, uint256 id);
    event LogDelete(address keeper, uint256 id);
    event LogMatch(uint256 id, uint256 amount);
}

/// @notice The core Rubicon Market smart contract
/// @notice This contract is based on the original open-source work done by OasisDEX under the Apache License 2.0
/// @dev This contract inherits the key trading functionality from SimpleMarket
contract RubiconMarket is MatchingEvents, ExpiringMarket, DSNote {
    bool public buyEnabled = true; //buy enabled
    bool public matchingEnabled = true; //true: enable matching,
    //false: revert to expiring market
    /// @dev Below is variable to allow for a proxy-friendly constructor
    bool public initialized;

    /// @dev unused deprecated variable for applying a token distribution on top of a trade
    bool public AqueductDistributionLive;
    /// @dev unused deprecated variable for applying a token distribution of this token on top of a trade
    address public AqueductAddress;

    struct sortInfo {
        uint256 next; //points to id of next higher offer
        uint256 prev; //points to id of previous lower offer
        uint256 delb; //the blocknumber where this entry was marked for delete
    }
    mapping(uint256 => sortInfo) public _rank; //doubly linked lists of sorted offer ids
    mapping(address => mapping(address => uint256)) public _best; //id of the highest offer for a token pair
    mapping(address => mapping(address => uint256)) public _span; //number of offers stored for token pair in sorted orderbook
    mapping(address => uint256) public _dust; //minimum sell amount for a token to avoid dust offers
    mapping(uint256 => uint256) public _near; //next unsorted offer id
    uint256 public _head; //first unsorted offer id
    uint256 public dustId; // id of the latest offer marked as dust

    struct dataPointInfo {
        uint CumulativePrice;
        uint CumulativeAssetA;
        uint CumulativeAssetB;
        uint Timestamp;
    }

    mapping(bytes32 => dataPointInfo[]) public oracleDataPoints;
    mapping(bytes32 => uint256) public nextTwapIndex;

    uint256 public constant maxTwapLength = 120;
    uint256 public constant TWAP_TIME_UPDATE_THRESHOLD = 30;

    /// @dev Proxy-safe initialization of storage
    function initialize(bool _live, address _feeTo) public {
        require(!initialized, "contract is already initialized");
        AqueductDistributionLive = _live;

        /// @notice The market fee recipient
        feeTo = _feeTo;

        owner = msg.sender;
        emit LogSetOwner(msg.sender);

        /// @notice The starting fee on taker trades in basis points
        feeBPS = 20;

        initialized = true;
        matchingEnabled = true;
        buyEnabled = true;
    }

    // After close, anyone can cancel an offer
    modifier can_cancel(uint256 id) override {
        require(isActive(id), "Offer was deleted or taken, or never existed.");
        require(
            isClosed() || msg.sender == getOwner(id) || id == dustId,
            "Offer can not be cancelled because user is not owner, and market is open, and offer sells required amount of tokens."
        );
        _;
    }

    // ---- Public entrypoints ---- //

    function make(
        ERC20 pay_gem,
        ERC20 buy_gem,
        uint128 pay_amt,
        uint128 buy_amt
    ) public override returns (bytes32) {
        return bytes32(offer(pay_amt, pay_gem, buy_amt, buy_gem));
    }

    function take(bytes32 id, uint128 maxTakeAmount) public override {
        require(buy(uint256(id), maxTakeAmount));
    }

    function kill(bytes32 id) external override {
        require(cancel(uint256(id)));
    }

    // Make a new offer. Takes funds from the caller into market escrow.
    //
    // If matching is enabled:
    //     * creates new offer without putting it in
    //       the sorted list.
    //     * available to authorized contracts only!
    //     * keepers should call insert(id,pos)
    //       to put offer in the sorted list.
    //
    // If matching is disabled:
    //     * calls expiring market's offer().
    //     * available to everyone without authorization.
    //     * no sorting is done.
    //
    function offer(
        uint256 pay_amt, //maker (ask) sell how much
        ERC20 pay_gem, //maker (ask) sell which token
        uint256 buy_amt, //taker (ask) buy how much
        ERC20 buy_gem //taker (ask) buy which token
    ) public override returns (uint256) {
        require(!locked, "Reentrancy attempt");


            function(uint256, ERC20, uint256, ERC20) returns (uint256) fn
         = matchingEnabled ? _offeru : super.offer;
        return fn(pay_amt, pay_gem, buy_amt, buy_gem);
    }

    // Make a new offer. Takes funds from the caller into market escrow.
    function offer(
        uint256 pay_amt, //maker (ask) sell how much
        ERC20 pay_gem, //maker (ask) sell which token
        uint256 buy_amt, //maker (ask) buy how much
        ERC20 buy_gem, //maker (ask) buy which token
        uint256 pos //position to insert offer, 0 should be used if unknown
    ) external can_offer returns (uint256) {
        return offer(pay_amt, pay_gem, buy_amt, buy_gem, pos, true);
    }

    function offer(
        uint256 pay_amt, //maker (ask) sell how much
        ERC20 pay_gem, //maker (ask) sell which token
        uint256 buy_amt, //maker (ask) buy how much
        ERC20 buy_gem, //maker (ask) buy which token
        uint256 pos, //position to insert offer, 0 should be used if unknown
        bool matching //match "close enough" orders?
    ) public can_offer returns (uint256) {
        require(!locked, "Reentrancy attempt");
        require(_dust[address(pay_gem)] <= pay_amt);

        if (matchingEnabled) {
            return _matcho(pay_amt, pay_gem, buy_amt, buy_gem, pos, matching);
        }
        return super.offer(pay_amt, pay_gem, buy_amt, buy_gem);
    }

    //Transfers funds from caller to offer maker, and from market to caller.
    function buy(uint256 id, uint256 amount)
        public
        override
        can_buy(id)
        returns (bool)
    {
        require(!locked, "Reentrancy attempt");

        //Optional distribution on trade
        if (AqueductDistributionLive) {
            IAqueduct(AqueductAddress).distributeToMakerAndTaker(
                getOwner(id),
                msg.sender
            );
        }
        function(uint256, uint256) returns (bool) fn = matchingEnabled
            ? _buys
            : super.buy;

        bool success = fn(id, amount);
        bytes32 ID = keccak256(abi.encodePacked(address(offers[id].buy_gem), address(offers[id].pay_gem)));
        if (success && block.timestamp > add(oracleDataPoints[ID][nextTwapIndex[ID] - 1].Timestamp, TWAP_TIME_UPDATE_THRESHOLD)) {
            uint buyPayRatio = mul(offers[id].buy_amt, WAD) / offers[id].pay_amt;
            _writeToTwapArray(ID, block.timestamp, buyPayRatio, offers[id].buy_amt, offers[id].pay_amt);
        }
        return success;
    }

    // Cancel an offer. Refunds offer maker.
    function cancel(uint256 id)
        public
        override
        can_cancel(id)
        returns (bool success)
    {
        require(!locked, "Reentrancy attempt");
        if (matchingEnabled) {
            if (isOfferSorted(id)) {
                require(_unsort(id));
            } else {
                require(_hide(id));
            }
        }
        return super.cancel(id); //delete the offer.
    }

    //insert offer into the sorted list
    //keepers need to use this function
    function insert(
        uint256 id, //maker (ask) id
        uint256 pos //position to insert into
    ) public returns (bool) {
        require(!locked, "Reentrancy attempt");
        require(!isOfferSorted(id)); //make sure offers[id] is not yet sorted
        require(isActive(id)); //make sure offers[id] is active

        _hide(id); //remove offer from unsorted offers list
        _sort(id, pos); //put offer into the sorted offers list
        emit LogInsert(msg.sender, id);
        return true;
    }

    //deletes _rank [id]
    //  Function should be called by keepers.
    function del_rank(uint256 id) external returns (bool) {
        require(!locked, "Reentrancy attempt");
        require(
            !isActive(id) &&
                _rank[id].delb != 0 &&
                _rank[id].delb < block.number - 10
        );
        delete _rank[id];
        emit LogDelete(msg.sender, id);
        return true;
    }

    //set the minimum sell amount for a token
    //    Function is used to avoid "dust offers" that have
    //    very small amount of tokens to sell, and it would
    //    cost more gas to accept the offer, than the value
    //    of tokens received.
    function setMinSell(
        ERC20 pay_gem, //token to assign minimum sell amount to
        uint256 dust //maker (ask) minimum sell amount
    ) external auth note returns (bool) {
        _dust[address(pay_gem)] = dust;
        emit LogMinSell(address(pay_gem), dust);
        return true;
    }

    //returns the minimum sell amount for an offer
    function getMinSell(
        ERC20 pay_gem //token for which minimum sell amount is queried
    ) external view returns (uint256) {
        return _dust[address(pay_gem)];
    }

    //set buy functionality enabled/disabled
    function setBuyEnabled(bool buyEnabled_) external auth returns (bool) {
        buyEnabled = buyEnabled_;
        emit LogBuyEnabled(buyEnabled);
        return true;
    }

    //set matching enabled/disabled
    //    If matchingEnabled true(default), then inserted offers are matched.
    //    Except the ones inserted by contracts, because those end up
    //    in the unsorted list of offers, that must be later sorted by
    //    keepers using insert().
    //    If matchingEnabled is false then RubiconMarket is reverted to ExpiringMarket,
    //    and matching is not done, and sorted lists are disabled.
    function setMatchingEnabled(bool matchingEnabled_)
        external
        auth
        returns (bool)
    {
        matchingEnabled = matchingEnabled_;
        emit LogMatchingEnabled(matchingEnabled);
        return true;
    }

    //return the best offer for a token pair
    //      the best offer is the lowest one if it's an ask,
    //      and highest one if it's a bid offer
    function getBestOffer(ERC20 sell_gem, ERC20 buy_gem)
        public
        view
        returns (uint256)
    {
        return _best[address(sell_gem)][address(buy_gem)];
    }

    //return the next worse offer in the sorted list
    //      the worse offer is the higher one if its an ask,
    //      a lower one if its a bid offer,
    //      and in both cases the newer one if they're equal.
    function getWorseOffer(uint256 id) public view returns (uint256) {
        return _rank[id].prev;
    }

    //return the next better offer in the sorted list
    //      the better offer is in the lower priced one if its an ask,
    //      the next higher priced one if its a bid offer
    //      and in both cases the older one if they're equal.
    function getBetterOffer(uint256 id) external view returns (uint256) {
        return _rank[id].next;
    }

    //return the amount of better offers for a token pair
    function getOfferCount(ERC20 sell_gem, ERC20 buy_gem)
        public
        view
        returns (uint256)
    {
        return _span[address(sell_gem)][address(buy_gem)];
    }

    //get the first unsorted offer that was inserted by a contract
    //      Contracts can't calculate the insertion position of their offer because it is not an O(1) operation.
    //      Their offers get put in the unsorted list of offers.
    //      Keepers can calculate the insertion position offchain and pass it to the insert() function to insert
    //      the unsorted offer into the sorted list. Unsorted offers will not be matched, but can be bought with buy().
    function getFirstUnsortedOffer() public view returns (uint256) {
        return _head;
    }

    //get the next unsorted offer
    //      Can be used to cycle through all the unsorted offers.
    function getNextUnsortedOffer(uint256 id) public view returns (uint256) {
        return _near[id];
    }

    function isOfferSorted(uint256 id) public view returns (bool) {
        return
            _rank[id].next != 0 ||
            _rank[id].prev != 0 ||
            _best[address(offers[id].pay_gem)][address(offers[id].buy_gem)] ==
            id;
    }

    function sellAllAmount(
        ERC20 pay_gem,
        uint256 pay_amt,
        ERC20 buy_gem,
        uint256 min_fill_amount
    ) external returns (uint256 fill_amt) {
        require(!locked, "Reentrancy attempt");
        uint256 offerId;
        while (pay_amt > 0) {
            //while there is amount to sell
            offerId = getBestOffer(buy_gem, pay_gem); //Get the best offer for the token pair
            require(offerId != 0); //Fails if there are not more offers

            // There is a chance that pay_amt is smaller than 1 wei of the other token
            if (
                pay_amt * 1 ether <
                wdiv(offers[offerId].buy_amt, offers[offerId].pay_amt)
            ) {
                break; //We consider that all amount is sold
            }
            if (pay_amt >= offers[offerId].buy_amt) {
                //If amount to sell is higher or equal than current offer amount to buy
                fill_amt = add(fill_amt, offers[offerId].pay_amt); //Add amount bought to acumulator
                pay_amt = sub(pay_amt, offers[offerId].buy_amt); //Decrease amount to sell
                take(bytes32(offerId), uint128(offers[offerId].pay_amt)); //We take the whole offer
            } else {
                // if lower
                uint256 baux = rmul(
                    pay_amt * 10**9,
                    rdiv(offers[offerId].pay_amt, offers[offerId].buy_amt)
                ) / 10**9;
                fill_amt = add(fill_amt, baux); //Add amount bought to acumulator
                take(bytes32(offerId), uint128(baux)); //We take the portion of the offer that we need
                pay_amt = 0; //All amount is sold
            }
        }
        require(fill_amt >= min_fill_amount);
    }

    function buyAllAmount(
        ERC20 buy_gem,
        uint256 buy_amt,
        ERC20 pay_gem,
        uint256 max_fill_amount
    ) external returns (uint256 fill_amt) {
        require(!locked, "Reentrancy attempt");
        uint256 offerId;
        while (buy_amt > 0) {
            //Meanwhile there is amount to buy
            offerId = getBestOffer(buy_gem, pay_gem); //Get the best offer for the token pair
            require(offerId != 0);

            // There is a chance that buy_amt is smaller than 1 wei of the other token
            if (
                buy_amt * 1 ether <
                wdiv(offers[offerId].pay_amt, offers[offerId].buy_amt)
            ) {
                break; //We consider that all amount is sold
            }
            if (buy_amt >= offers[offerId].pay_amt) {
                //If amount to buy is higher or equal than current offer amount to sell
                fill_amt = add(fill_amt, offers[offerId].buy_amt); //Add amount sold to acumulator
                buy_amt = sub(buy_amt, offers[offerId].pay_amt); //Decrease amount to buy
                take(bytes32(offerId), uint128(offers[offerId].pay_amt)); //We take the whole offer
            } else {
                //if lower
                fill_amt = add(
                    fill_amt,
                    rmul(
                        buy_amt * 10**9,
                        rdiv(offers[offerId].buy_amt, offers[offerId].pay_amt)
                    ) / 10**9
                ); //Add amount sold to acumulator
                take(bytes32(offerId), uint128(buy_amt)); //We take the portion of the offer that we need
                buy_amt = 0; //All amount is bought
            }
        }
        require(fill_amt <= max_fill_amount);
    }

    function getBuyAmount(
        ERC20 buy_gem,
        ERC20 pay_gem,
        uint256 pay_amt
    ) external view returns (uint256 fill_amt) {
        uint256 offerId = getBestOffer(buy_gem, pay_gem); //Get best offer for the token pair
        while (pay_amt > offers[offerId].buy_amt) {
            fill_amt = add(fill_amt, offers[offerId].pay_amt); //Add amount to buy accumulator
            pay_amt = sub(pay_amt, offers[offerId].buy_amt); //Decrease amount to pay
            if (pay_amt > 0) {
                //If we still need more offers
                offerId = getWorseOffer(offerId); //We look for the next best offer
                require(offerId != 0); //Fails if there are not enough offers to complete
            }
        }
        fill_amt = add(
            fill_amt,
            rmul(
                pay_amt * 10**9,
                rdiv(offers[offerId].pay_amt, offers[offerId].buy_amt)
            ) / 10**9
        ); //Add proportional amount of last offer to buy accumulator
    }

    function getPayAmount(
        ERC20 pay_gem,
        ERC20 buy_gem,
        uint256 buy_amt
    ) external view returns (uint256 fill_amt) {
        uint256 offerId = getBestOffer(buy_gem, pay_gem); //Get best offer for the token pair
        while (buy_amt > offers[offerId].pay_amt) {
            fill_amt = add(fill_amt, offers[offerId].buy_amt); //Add amount to pay accumulator
            buy_amt = sub(buy_amt, offers[offerId].pay_amt); //Decrease amount to buy
            if (buy_amt > 0) {
                //If we still need more offers
                offerId = getWorseOffer(offerId); //We look for the next best offer
                require(offerId != 0); //Fails if there are not enough offers to complete
            }
        }
        fill_amt = add(
            fill_amt,
            rmul(
                buy_amt * 10**9,
                rdiv(offers[offerId].buy_amt, offers[offerId].pay_amt)
            ) / 10**9
        ); //Add proportional amount of last offer to pay accumulator
    }

    // ---- Internal Functions ---- //

    function _buys(uint256 id, uint256 amount) internal returns (bool) {
        require(buyEnabled);
        if (amount == offers[id].pay_amt) {
            if (isOfferSorted(id)) {
                //offers[id] must be removed from sorted list because all of it is bought
                _unsort(id);
            } else {
                _hide(id);
            }
        }

        require(super.buy(id, amount));

        // If offer has become dust during buy, we cancel it
        if (
            isActive(id) &&
            offers[id].pay_amt < _dust[address(offers[id].pay_gem)]
        ) {
            dustId = id; //enable current msg.sender to call cancel(id)
            cancel(id);
        }
        return true;
    }

    //find the id of the next higher offer after offers[id]
    function _find(uint256 id) internal view returns (uint256) {
        require(id > 0);

        address buy_gem = address(offers[id].buy_gem);
        address pay_gem = address(offers[id].pay_gem);
        uint256 top = _best[pay_gem][buy_gem];
        uint256 old_top = 0;

        // Find the larger-than-id order whose successor is less-than-id.
        while (top != 0 && _isPricedLtOrEq(id, top)) {
            old_top = top;
            top = _rank[top].prev;
        }
        return old_top;
    }

    //find the id of the next higher offer after offers[id]
    function _findpos(uint256 id, uint256 pos) internal view returns (uint256) {
        require(id > 0);

        // Look for an active order.
        while (pos != 0 && !isActive(pos)) {
            pos = _rank[pos].prev;
        }

        if (pos == 0) {
            //if we got to the end of list without a single active offer
            return _find(id);
        } else {
            // if we did find a nearby active offer
            // Walk the order book down from there...
            if (_isPricedLtOrEq(id, pos)) {
                uint256 old_pos;

                // Guaranteed to run at least once because of
                // the prior if statements.
                while (pos != 0 && _isPricedLtOrEq(id, pos)) {
                    old_pos = pos;
                    pos = _rank[pos].prev;
                }
                return old_pos;

                // ...or walk it up.
            } else {
                while (pos != 0 && !_isPricedLtOrEq(id, pos)) {
                    pos = _rank[pos].next;
                }
                return pos;
            }
        }
    }

    //return true if offers[low] priced less than or equal to offers[high]
    function _isPricedLtOrEq(
        uint256 low, //lower priced offer's id
        uint256 high //higher priced offer's id
    ) internal view returns (bool) {
        return
            mul(offers[low].buy_amt, offers[high].pay_amt) >=
            mul(offers[high].buy_amt, offers[low].pay_amt);
    }

    //these variables are global only because of solidity local variable limit

    //match offers with taker offer, and execute token transactions
    function _matcho(
        uint256 t_pay_amt, //taker sell how much
        ERC20 t_pay_gem, //taker sell which token
        uint256 t_buy_amt, //taker buy how much
        ERC20 t_buy_gem, //taker buy which token
        uint256 pos, //position id
        bool rounding //match "close enough" orders?
    ) internal returns (uint256 id) {
        uint256 best_maker_id; //highest maker id
        uint256 t_buy_amt_old; //taker buy how much saved
        uint256 m_buy_amt; //maker offer wants to buy this much token
        uint256 m_pay_amt; //maker offer wants to sell this much token

        // there is at least one offer stored for token pair
        while (_best[address(t_buy_gem)][address(t_pay_gem)] > 0) {
            best_maker_id = _best[address(t_buy_gem)][address(t_pay_gem)];
            m_buy_amt = offers[best_maker_id].buy_amt;
            m_pay_amt = offers[best_maker_id].pay_amt;

            // Ugly hack to work around rounding errors. Based on the idea that
            // the furthest the amounts can stray from their "true" values is 1.
            // Ergo the worst case has t_pay_amt and m_pay_amt at +1 away from
            // their "correct" values and m_buy_amt and t_buy_amt at -1.
            // Since (c - 1) * (d - 1) > (a + 1) * (b + 1) is equivalent to
            // c * d > a * b + a + b + c + d, we write...
            if (
                mul(m_buy_amt, t_buy_amt) >
                mul(t_pay_amt, m_pay_amt) +
                    (
                        rounding
                            ? m_buy_amt + t_buy_amt + t_pay_amt + m_pay_amt
                            : 0
                    )
            ) {
                break;
            }
            // ^ The `rounding` parameter is a compromise borne of a couple days
            // of discussion.
            buy(best_maker_id, min(m_pay_amt, t_buy_amt));
            emit LogMatch(id, min(m_pay_amt, t_buy_amt));
            t_buy_amt_old = t_buy_amt;
            t_buy_amt = sub(t_buy_amt, min(m_pay_amt, t_buy_amt));
            t_pay_amt = mul(t_buy_amt, t_pay_amt) / t_buy_amt_old;

            if (t_pay_amt == 0 || t_buy_amt == 0) {
                break;
            }
        }

        if (
            t_buy_amt > 0 &&
            t_pay_amt > 0 &&
            t_pay_amt >= _dust[address(t_pay_gem)]
        ) {
            //new offer should be created
            id = super.offer(t_pay_amt, t_pay_gem, t_buy_amt, t_buy_gem);
            //insert offer into the sorted list
            _sort(id, pos);
        }
    }

    // Make a new offer without putting it in the sorted list.
    // Takes funds from the caller into market escrow.
    // Keepers should call insert(id,pos) to put offer in the sorted list.
    function _offeru(
        uint256 pay_amt, //maker (ask) sell how much
        ERC20 pay_gem, //maker (ask) sell which token
        uint256 buy_amt, //maker (ask) buy how much
        ERC20 buy_gem //maker (ask) buy which token
    ) internal returns (uint256 id) {
        require(_dust[address(pay_gem)] <= pay_amt);
        id = super.offer(pay_amt, pay_gem, buy_amt, buy_gem);
        _near[id] = _head;
        _head = id;
        emit LogUnsortedOffer(id);
    }

    //put offer into the sorted list
    function _sort(
        uint256 id, //maker (ask) id
        uint256 pos //position to insert into
    ) internal {
        require(isActive(id));

        ERC20 buy_gem = offers[id].buy_gem;
        ERC20 pay_gem = offers[id].pay_gem;
        uint256 prev_id; //maker (ask) id

        pos = pos == 0 ||
            offers[pos].pay_gem != pay_gem ||
            offers[pos].buy_gem != buy_gem ||
            !isOfferSorted(pos)
            ? _find(id)
            : _findpos(id, pos);

        if (pos != 0) {
            //offers[id] is not the highest offer
            //requirement below is satisfied by statements above
            //require(_isPricedLtOrEq(id, pos));
            prev_id = _rank[pos].prev;
            _rank[pos].prev = id;
            _rank[id].next = pos;
        } else {
            //offers[id] is the highest offer
            prev_id = _best[address(pay_gem)][address(buy_gem)];
            _best[address(pay_gem)][address(buy_gem)] = id;
        }

        if (prev_id != 0) {
            //if lower offer does exist
            //requirement below is satisfied by statements above
            //require(!_isPricedLtOrEq(id, prev_id));
            _rank[prev_id].next = id;
            _rank[id].prev = prev_id;
        }

        _span[address(pay_gem)][address(buy_gem)]++;
        emit LogSortedOffer(id);
    }

    // Remove offer from the sorted list (does not cancel offer)
    function _unsort(
        uint256 id //id of maker (ask) offer to remove from sorted list
    ) internal returns (bool) {
        address buy_gem = address(offers[id].buy_gem);
        address pay_gem = address(offers[id].pay_gem);
        require(_span[pay_gem][buy_gem] > 0);

        require(
            _rank[id].delb == 0 && //assert id is in the sorted list
                isOfferSorted(id)
        );

        if (id != _best[pay_gem][buy_gem]) {
            // offers[id] is not the highest offer
            require(_rank[_rank[id].next].prev == id);
            _rank[_rank[id].next].prev = _rank[id].prev;
        } else {
            //offers[id] is the highest offer
            _best[pay_gem][buy_gem] = _rank[id].prev;
        }

        if (_rank[id].prev != 0) {
            //offers[id] is not the lowest offer
            require(_rank[_rank[id].prev].next == id);
            _rank[_rank[id].prev].next = _rank[id].next;
        }

        _span[pay_gem][buy_gem]--;
        _rank[id].delb = block.number; //mark _rank[id] for deletion
        return true;
    }

    //Hide offer from the unsorted order book (does not cancel offer)
    function _hide(
        uint256 id //id of maker offer to remove from unsorted list
    ) internal returns (bool) {
        uint256 uid = _head; //id of an offer in unsorted offers list
        uint256 pre = uid; //id of previous offer in unsorted offers list

        require(!isOfferSorted(id)); //make sure offer id is not in sorted offers list

        if (_head == id) {
            //check if offer is first offer in unsorted offers list
            _head = _near[id]; //set head to new first unsorted offer
            _near[id] = 0; //delete order from unsorted order list
            return true;
        }
        while (uid > 0 && uid != id) {
            //find offer in unsorted order list
            pre = uid;
            uid = _near[uid];
        }
        if (uid != id) {
            //did not find offer id in unsorted offers list
            return false;
        }
        _near[pre] = _near[id]; //set previous unsorted offer to point to offer after offer id
        _near[id] = 0; //delete order from unsorted order list
        return true;
    }

    function setFeeBPS(uint256 _newFeeBPS) external auth returns (bool) {
        feeBPS = _newFeeBPS;
        return true;
    }

    /// @dev unused deprecated function for applying a token distribution on top of a trade
    function setAqueductDistributionLive(bool live)
        external
        auth
        returns (bool)
    {
        AqueductDistributionLive = live;
        return true;
    }

    /// @dev unused deprecated variable for applying a token distribution on top of a trade
    function setAqueductAddress(address _Aqueduct)
        external
        auth
        returns (bool)
    {
        AqueductAddress = _Aqueduct;
        return true;
    }

    function setFeeTo(address newFeeTo) external auth returns (bool) {
        feeTo = newFeeTo;
        return true;
    }

    function getTWAP(ERC20 buy_gem, ERC20 pay_gem, uint _duration) public view returns(uint) {
        bytes32 ID = keccak256(abi.encodePacked(address(buy_gem), address(pay_gem)));
        uint dataPointIndex = _findIndex(ID, _duration);
        uint span = sub(nextTwapIndex[ID] - 1, dataPointIndex);
        uint difference = sub(oracleDataPoints[ID][nextTwapIndex[ID] - 1].CumulativePrice, oracleDataPoints[ID][dataPointIndex].CumulativePrice);
        return difference / span;
    }

    function getVWAP(ERC20 buy_gem, ERC20 pay_gem, uint _duration) public view returns(uint) {
        bytes32 ID = keccak256(abi.encodePacked(address(buy_gem), address(pay_gem)));
        uint dataPointIndex = _findIndex(ID, _duration);
        uint assetADifference = sub(oracleDataPoints[ID][nextTwapIndex[ID] - 1].CumulativeAssetA, oracleDataPoints[ID][dataPointIndex].CumulativeAssetA);
        uint assetBDifference = sub(oracleDataPoints[ID][nextTwapIndex[ID] - 1].CumulativeAssetB, oracleDataPoints[ID][dataPointIndex].CumulativeAssetB);
        uint ratio = mul(assetADifference, WAD) / assetBDifference; 
        return ratio;
    }

    function getAWAP(ERC20 buy_gem, ERC20 pay_gem, uint _duration, uint _twapWeighting) public view returns(uint) {
        require(_twapWeighting <= WAD);
        uint vwap = getVWAP(buy_gem, pay_gem, _duration);
        uint twap = getTWAP(buy_gem, pay_gem, _duration);
        if (_twapWeighting == 0) {
            return vwap;
        } else if (_twapWeighting == WAD) {
            return twap;
        }
        uint vwapWeighting = sub(WAD, _twapWeighting);
        uint weightedTwap = mul(twap, _twapWeighting) / WAD;
        uint weightedVwap = mul(vwap, vwapWeighting) / WAD;
        uint weightedProduct = mul(weightedTwap, weightedVwap) / WAD;
        uint weightedPrice = sqrtu(weightedProduct);
        return weightedPrice;
    }

    function _findIndex(bytes32 _ID, uint _duration) internal view returns(uint) {
        uint base = sub(block.timestamp, _duration);
        dataPointInfo[] memory data = oracleDataPoints[_ID];
        uint pivot = nextTwapIndex[_ID] - 1;
        if (pivot == data.length - 1) {
            (uint index, ) = _binarySearch(data, 0, data.length - 1, base);
            return index;
        }
        (uint bestLowerIndex, uint lowerDif) = _binarySearch(data, 0, pivot - 1, base);
        (uint bestUpperIndex, uint upperDif) = _binarySearch(data, pivot + 1, data.length - 1, base);
        uint returnVal = upperDif < lowerDif ? bestUpperIndex : bestLowerIndex;
        return returnVal;
    }

    function _binarySearch(dataPointInfo[] memory _array, uint _low, uint _high, uint _key) internal view returns(uint, uint) {
        uint mid = add(_low, _high) / 2;
        uint best = mid;
        int bestDifference = abs(int(_array[mid].Timestamp) - int(_key));
        while (_low != _high) {
            mid = add(_low, _high) / 2;
            int dif = abs(int(_array[mid].Timestamp) - int(_key));
            if (dif < bestDifference) {
                best = mid;
                bestDifference = dif;
            }
            if (abs(int(_array[mid + 1].Timestamp) - int(_key)) < dif) {
                _low = mid;
            } else if (abs(int(_array[mid - 1].Timestamp) - int(_key)) < dif) {
                _high = mid;
            } else {
                return (mid, uint(dif));
            }
        }
        return (best, uint(bestDifference));
    }

    function _writeToTwapArray(bytes32 _ID, uint _timestamp, uint _price, uint _assetA, uint _assetB) internal {
        dataPointInfo memory point = dataPointInfo(
            _price,
            _timestamp,
            _assetA,
            _assetB
        );
        uint len = oracleDataPoints[_ID].length;
        if (len == 0) {
            oracleDataPoints[_ID].push(point);
        } else if (len < maxTwapLength) {
            uint newTotal = add(oracleDataPoints[_ID][len - 1].CumulativePrice, _price);
            uint newVolumeA = add(oracleDataPoints[_ID][len - 1].CumulativeAssetA, _assetA);
            uint newVolumeB = add(oracleDataPoints[_ID][len - 1].CumulativeAssetB, _assetB);
            point.CumulativePrice = newTotal;
            point.CumulativeAssetA = newVolumeA;
            point.CumulativeAssetB = newVolumeB;
            oracleDataPoints[_ID].push(point);
        } else {
            uint lastIndex = nextTwapIndex[_ID] == 0 ? (maxTwapLength - 1) : (nextTwapIndex[_ID] - 1);
            uint newTotal = add(oracleDataPoints[_ID][lastIndex].CumulativePrice, _price);
            uint newVolumeA = add(oracleDataPoints[_ID][lastIndex].CumulativeAssetA, _assetA);
            uint newVolumeB = add(oracleDataPoints[_ID][lastIndex].CumulativeAssetB, _assetB);
            point.CumulativePrice = newTotal;
            point.CumulativeAssetA = newVolumeA;
            point.CumulativeAssetB = newVolumeB;
            oracleDataPoints[_ID][nextTwapIndex[_ID]] = point;
            nextTwapIndex[_ID] = nextTwapIndex[_ID] == (maxTwapLength - 1) ? 0 : nextTwapIndex[_ID] + 1;
        }
    }

      function sqrtu (uint256 x) private pure returns (uint128) {
        if (x == 0) return 0;
        else {
          uint256 xx = x;
          uint256 r = 1;
          if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
          if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
          if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
          if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
          if (xx >= 0x100) { xx >>= 8; r <<= 4; }
          if (xx >= 0x10) { xx >>= 4; r <<= 2; }
          if (xx >= 0x8) { r <<= 1; }
          r = (r + x / r) >> 1;
          r = (r + x / r) >> 1;
          r = (r + x / r) >> 1;
          r = (r + x / r) >> 1;
          r = (r + x / r) >> 1;
          r = (r + x / r) >> 1;
          r = (r + x / r) >> 1; // Seven iterations should be enough
          uint256 r1 = x / r;
          return uint128 (r < r1 ? r : r1);
        }
      }

    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }
}

/// @title StopLossManager for RubiconMarket
/// @notice This contract manages stop loss orders as an extension of the RubiconMarket contract
/// @dev Utilizes DSMath for safe math operations
contract StopLossManager is DSMath {

    /// @dev Below is the instance of RubiconMarket that this contract will make calls to
    RubiconMarket internal market;

    /// @dev Below is a customizable mapping by the maker of an order which is the ratio of buy_amt to pay_amt at which to allow strategists to execute order
    mapping(uint => uint) public stopLossRatio;

    /// @dev Below is a mapping from an address to a boolean indicating if an address is a strategist
    mapping(address => bool) public isStrategist;

    /// @dev Below is the address of the owner (Rubicon team)
    address public Owner;

    /// @dev Below is the fee to incentivize strategists to execute stop loss orders
    uint public STOP_LOSS_FEE;

    /// @dev Below is the duration over which to calculate the AWAP for market price over
    uint public twapDuration;

    /// @dev Below is the twap vs vwap weighting to calculate for the AWAP
    uint public twapWeighting;

    /// @dev Belos is the fee in basis points charged on taker trades
    uint internal feeBPS;

    /// @dev Below is variable to allow for a proxy-friendly constructor
    bool public initialized;

    /// @dev Proxy-safe initialization of storage
    /// @param _market address of RubiconMarket instance
    /// @param _fee amount of ether to be required as a fee for stop loss orders, initially
    function initialize(address _market, uint _fee, uint _twapDuration, uint _twapWeighting) external {
        require(!initialized);
        Owner = msg.sender;
        market = RubiconMarket(_market);
        STOP_LOSS_FEE = _fee;
        twapDuration = _twapDuration;
        twapWeighting = _twapWeighting;
        feeBPS = 20;
        initialized = true;
    }

    /// @dev Allow for contract to receive native ether payments
    receive() external payable {}

    /// @notice The owner of an order can set their stop loss ratio and provide a fee to incentivize strategists to execute it
    /// @param _id identifier of order in the RubiconMarket contract
    /// @param _ratio ratio of buy_amt to pay_amt of best offer on the market for buy_gem and pay_gem at which strategists are incentivized to execute order
    function makeStopLossOrder(uint _id, uint _ratio) external payable {
        require(_ratio != 0);
        address owner = market.getOwner(_id);
        require(msg.sender == owner);
        (uint pay_amt, , uint buy_amt,) = market.getOffer(_id);
        require(mul(buy_amt, WAD) / pay_amt < _ratio);
        require(msg.value >= STOP_LOSS_FEE);
        stopLossRatio[_id] = _ratio;
        if (msg.value > STOP_LOSS_FEE) {
            uint amt = sub(msg.value, STOP_LOSS_FEE);
            refund(amt);
        }
    }

    /// @notice After placing a stop loss order, the maker can cancel the order and take back the fee they paid to place the order
    /// @param _id Key in stopLossRatio mapping to point to 0
    function cancelStopLossOrder(uint _id) external {
        require(stopLossRatio[_id] > 0);
        address owner = market.getOwner(_id);
        require(msg.sender == owner);
        stopLossRatio[_id] = 0;
        refund(STOP_LOSS_FEE);
    }

    /// @notice Only strategists may call this function and will be paid a fee to close out the order
    /// @param _id Identifier of order to fill on RubiconMarket
    function fillStopLossOrder(uint _id) external {
        require(isStrategist[msg.sender]);
        require(detectStopLossHit(_id));
        (uint pay_amt, ERC20 pay_gem, uint buy_amt, ERC20 buy_gem) = market.getOffer(_id);
        uint spend = mul(buy_amt, buy_amt) / pay_amt;
        uint fee = mul(spend, feeBPS) / 10000;
        require(buy_gem.transferFrom(msg.sender, address(this), add(fee, spend)));
        market.buy(_id, buy_amt);
        payable(msg.sender).transfer(STOP_LOSS_FEE);
        pay_gem.transfer(msg.sender, pay_amt);
    }

    /// @notice Internal function to determine if market ratio of buy_gem to pay_gem is less than stop loss ratio placed by maker
    /// @param _id Key in stopLossRatio mapping to observe
    function detectStopLossHit(uint _id) public view returns(bool success) {
        uint stopLoss = stopLossRatio[_id];
        require(stopLoss > 0);
        (, ERC20 pay_gem, , ERC20 buy_gem) = market.getOffer(_id);
        uint ratio = market.getAWAP(pay_gem, buy_gem, twapDuration, twapWeighting);
        success = ratio <= stopLoss;
    }

    /// @notice External function only callable by owner of contract to whitelist certain addresses to fill stop loss orders
    /// @param _strategist Address to allow as strategist
    function allowStrategist(address _strategist) external {
        require(msg.sender == Owner);
        isStrategist[_strategist] = true;
    }

    /// @notice External function only callable by owner of contract to change feeBPS according to RubiconMarket
    /// @param _newFeeBPS New fee being charged on taker trades
    function setFeeBPS(uint _newFeeBPS) internal {
        feeBPS = _newFeeBPS;
    }

    /// @notice Internal utility function to send funds held by the contract to caller of a function in special cases
    /// @param _amount Amount of ether to be sent
    function refund(uint _amount) internal {
        payable(msg.sender).transfer(_amount);
    }

    /// @notice External view function of stop loss ratios set by makers
    /// @param _id Key in the mapping of stop loss order that is wished to view
    function viewStopLossRatio(uint _id) external view returns(uint ratio) {
        ratio = stopLossRatio[_id];
    }
}

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;

    function approve(address guy, uint256 wad) external returns (bool);
}

interface IAqueduct {
    function distributeToMakerAndTaker(address maker, address taker)
        external
        returns (bool);
}
