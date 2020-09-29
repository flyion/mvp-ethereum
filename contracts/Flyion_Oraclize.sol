pragma solidity ^0.5.0;

/// 5.7M gas


///=== IMPORTS & INTERFACES =====
import "./oraclizeAPI.sol"; //NEEDED
import "./Flyion_Basics.sol";

contract MSC_Interface { //Using an interface to interact with the MSC
    function updateFromOracle(bytes32 _policyId, bytes32 _flightId, uint256 _actualArrDte, uint8 _fltStatus) public; //payable ?
    //IMPORTANT: Oraclize contract needs to know the MSC address and have authorization to interact with it.
}

///=== CONTRACT CODE =====
contract Flyion_Oraclize is usingFlyionBasics, usingOraclize { //inherits  Ownable, Authorizable
using SafeMath for uint; //needed with oraclize

//-- EVENTS:
event LogArrivalUpdated(string _fltNum, uint256 actualArrDte, uint256 flightDelayCalc);
event LogNewOraclizeQuery(bytes32 queryId);
event LogCallbackOraclize(bytes32 query, uint256 actualArrDte);

//-- PUBLIC VARIABLES:
/* UNUSED API KEYS ENCRYPTIONS: used to spin off new MSC contracts, each key can be used only once (1 contract deployment => 1 key)
*/
string private apiKey = "BMB5bcxZaNqdrfQk18PYlk54zbeef12eZxmHfv+DIDwXqu+1OMK4QT+rwV3iCaTClgX1Onbjgj0rnbfDVbWubeYUtfuqmQJ49A7hnMVh6uj4AXcSCe+SBXTzv3ELK+262HqyaVauWkFfkQyb6nhaCpVDjDVPySEU8r52817hslrHVy7v4VN15Q==";
string private username = "BOsMhfIjiqYIfjs0WS4tXDtk3uGuchw6NYvU3fk/r8ytOpH6w+tJ0Aft4uUOS3e4JbA+er4E3JI+lbeiXbfl8EImzQVy1RPfcjEAYTdv4h9dsEyzRnisAaLH1bs6+d4=";

//replace it by the ones at the top for each new contract

//MANUAL OVERRIDE of the ORACLE FUNCTION
bool public _MSC_update = true; //blocks MSC update. For testing of the Oraclize solution

//-- STRUCTS & MAPPINGS:
//Policies:
struct PolicyInformation {  //key = policyId.
    address originAddress;  //MSC source of the _policyId
    bytes32 policyId;       //duplicate used for REMIX interactions (view the struct)
    bytes32 flightId;       //fight Id (can be resolved from fltNum and depDte)
    bytes32 queryId;        //Oraclize queryId
}
mapping (bytes32 => PolicyInformation) public Policies; //list of all the Oracle queries,see struct for details.
bytes32[] public ArrayOfPolicies; //logs all the policies 1 policyId = 1 queryId = flightId

//Flights:
struct FlightInformation{ //key = _FlightId aiming at this flight.
  string fltNum; //name of the flight
  uint256 depDte; //departure date (local time)
  uint256 expectedArrDte; //expected arrival time (given when calling function)
  uint256 actualArrDte; //Actual arrival date (updated when <> 0, local time)
  uint256 calculatedDelay; //delay calculated form variables (redundant info for tests)
  uint8 fltSts; //flight status (0=unknown, 1=on-time, 2=delay, 3=other). Updated by Oracle or manually //oraclize queryID (appears once actualArrDte is updated)
}
mapping (bytes32 => FlightInformation) public Flights; //list of all the flights updated by this Oracle, see struct for details. //note: we can use Flightaware FlightID in the future.
bytes32[] public ArrayOfFlights; //logs all the Flights

//Queries:
struct QueryInformation {   //key = queryId
    bytes32 policyId;       //policy being resolved
    bool pendingQuery;      //true = query not
    uint256 lastUpdated;}   //blocks.timestamp
mapping (bytes32 => QueryInformation) public Queries;
//no array needed here (do we need to count ?)


//-- SETUP functions:
    function() external payable {} //callback

    constructor() public payable {
        require (msg.value > 0); //send ETH to be able to pay Oraclize.
        addAuthorized(msg.sender); // not needed ?
    }

//-- ORACLE functions:

//Oracle "update" demand -> triggered from the MSC (MSC sends _policyId as parameter).

    function triggerOracle(
        bytes32 _policyId,
        string memory _fltNum,
        uint256 _depDte,
        uint256 _expectedArrDte,
        uint256 _updateDelayTime,
        address _MSCaddress
    ) public payable onlyAuthorized { // payable to pay Oraclize to run functions, public allows manual trigger //-> external , calldata

    //create temporary _flightId & update variables (calls oraclize if variable _Oraclize != 0)
        bytes32 _flightId = createFlightId(_fltNum, _depDte); //using Flyion_Basics method

    //update of our internal mappings: Policy and Flights
        ArrayOfPolicies.push(_policyId);
        Policies[_policyId].originAddress = _MSCaddress; //required for callback activation
        Policies[_policyId].flightId = _flightId;  //updates queries database

        ArrayOfFlights.push(_flightId);
        Flights[_flightId].fltNum = _fltNum;
        Flights[_flightId].depDte = _depDte;
        Flights[_flightId].expectedArrDte = _expectedArrDte; //for tests & manual input
      //These should be initialized at zero by design
        //Flights[_flightId].calculatedDelay = 0
        //Flights[_flightId].actualArrDte = 0; //we don't know at this stage
        //Flights[_flightId].fltSts = 0; //flight status (0=unknown, 1=on-time, 2=delay, 3=other).

        //build and run query
        string memory fQry = strConcat("[URL] ['json(https://${[decrypt] ", username, "}:${[decrypt] ", apiKey, "}@flightxml.flightaware.com/json/FlightXML2/FlightInfoEx?ident=");
        string memory dPrt = "%40";
        string memory eQry = ").FlightInfoExResult.flights.0.estimatedarrivaltime']";
        string memory query = strConcat(fQry, _fltNum, dPrt, uint2str(_depDte), eQry);

        //-> triggers oraclize query (results will arrive with the callback = later)

        //UPDATE: Need to define custom GAS limits for the query: 200,000 for 1 client.
        //based on maxnbSeats in the POLICY x gasCost to transfer tokens.
        //USE of a STATIC of 20 seats to start (no need to call the MSC information yet)
        //100,000 gas for the payment looks like the norm
        // we Put 150,000 to be safe
        // we should be OK with -> 4M GAS. ORACLIZE will not take more than needed anyway.

        uint256 CUSTOM_GASLIMIT = 4000000;

        bytes32 _queryId = oraclize_query(_updateDelayTime, "nested", query, CUSTOM_GASLIMIT);
        emit LogNewOraclizeQuery(_queryId);
        
        //update of Queries and Policies:
        Queries[_queryId].policyId = _policyId;
        Queries[_queryId].pendingQuery = true;   //"true" = query is pending (oraclize did not answer back)
        Queries[_queryId].lastUpdated = 0;       //not yet updated

        Policies[Queries[_queryId].policyId].queryId = _queryId;  //direct use of _policyId GENERATES "STACK TOO DEEP"
    }

    //Oracle "callback"
    function __callback(bytes32 queryId, string memory __actualArrDte) public { //original code for oraclize callback
        //only Oraclize can trigger:
        require(msg.sender == oraclize_cbAddress(), "Must be Oraclize");

        if(_MSC_update == true) {
            updateMSC(queryId,__actualArrDte);
        }
        _MSC_update = true; //updates it back to normal for future use
    }

    function updateMSC(bytes32 queryId, string memory __actualArrDte) internal {

    //make sure we have a date returned (not zero)
        uint256 actualArrDte = parseInt(__actualArrDte); // use parseint(_actualArrDte) when from oracle, need to importe oraclizeAPI.sol
        require(actualArrDte > 0, "actualArrDte cannot be zero"); //we have a flight arrival date confirmed.
        //require (oraclizeQueries[queryId].pendingQuery == true); //query needs to be pending to be updatable

    //update local variables
        bytes32 _policyId = Queries[queryId].policyId;
        Policies[_policyId].queryId = queryId;  //updates Policies database

        bytes32 _flightId = Policies[_policyId].flightId; //retrieve the flightId from the queryId

        (uint256 _flightDelay, uint8 _fltSts) = updateFlightDelay(actualArrDte, Flights[_flightId].expectedArrDte);
        Flights[_flightId].actualArrDte = actualArrDte;
        Flights[_flightId].calculatedDelay = _flightDelay;
        Flights[_flightId].fltSts = _fltSts;

        //close query (pending= false) and make updated time (callback received)
        Queries[queryId].pendingQuery = false; // This effectively marks the queryId as processed.
        Queries[queryId].lastUpdated = block.timestamp; //note: we could use block.number too

        emit LogArrivalUpdated(Flights[_flightId].fltNum, actualArrDte, _flightDelay);

        //send info into MSC, use public variable to trigger functions or not
        if(PAYMT > 0){
            MSC_Interface(Policies[_policyId].originAddress).updateFromOracle(_policyId, _flightId, actualArrDte, _fltSts);
        }

    } //real oraclize callback.


//-- ADMIN functions
    function killContract() public onlyAuthorized {
        selfdestruct(msg.sender); //
    }
    function withdrawTokens(address _tokenAddress) public onlyOwner returns (uint256 _withdrawal) {
        _withdrawal = ERC20_Interface(_tokenAddress).balanceOf(address(this));
        ERC20_Interface(_tokenAddress).transfer(msg.sender, _withdrawal);
    }

//-- TESTING functions
    function ___getInfoFromPolicy(bytes32 _policyId) public view
    returns (string memory fltNum, uint256 depDte, uint256 expectedArrDte,
    uint256 actualArrDte, uint256 fltSts, uint256 calculatedDelay,
    bool _pendingQuery, uint256 _dateLastUpdated) {

            bytes32 _flightId = Policies[_policyId].flightId;
            bytes32 _queryId = Policies[_policyId].queryId;

        return(
            Flights[_flightId].fltNum,
            Flights[_flightId].depDte,
            Flights[_flightId].expectedArrDte,
            Flights[_flightId].actualArrDte,
            Flights[_flightId].fltSts,
            Flights[_flightId].calculatedDelay,
            Queries[_queryId].pendingQuery,   //"true" = query is pending (oraclize did not answer back)
            Queries[_queryId].lastUpdated
            );
    }


    function manualCallOracle(string memory _fltNum, uint256 _depDte, uint256 _updateTime, bool __MSC_update) //put _PAYMT = 0 to cancel oraclize call
    public payable onlyOwner{
        _MSC_update = __MSC_update;

        //build and run query
        string memory fQry = strConcat("[URL] ['json(https://${[decrypt] ", apiKey, "}@flightxml.flightaware.com/json/FlightXML2/FlightInfoEx?ident=");
        string memory dPrt = "%40";
        string memory eQry = ").FlightInfoExResult.flights.0.actualarrivaltime']";
        string memory query = strConcat(fQry, _fltNum, dPrt, uint2str(_depDte), eQry);
        oraclize_query(_updateTime+1, "nested", query); //10 seconds update delay time
        //-> WILL trigger the oracle callback
        //if _MSC_update = true, updateMSC() function will THROW if no policyId has been created 1st.
        }


///=== END OF CODE =====
}
