pragma solidity ^0.5.0;

//Set of common functions to import is MSC and ORACLE.
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

//ERC20 interface
contract ERC20_Interface {
    function balanceOf(address tokenOwner) public view returns (uint balance);
    function transfer(address to, uint tokens) public returns (bool success);
    event Transfer(address indexed from, address indexed to, uint tokens);
    function buyProduct(address shopId, uint price, bytes32 product) public payable returns (bool success);
}

//Authorizable
contract Authorizable is Ownable {

    mapping(address => bool) public authorized;
    address[] public authorizedList;


    modifier onlyAuthorized() {
        require(authorized[msg.sender] || owner() == msg.sender);
        _;
    }

    function addAuthorized(address _toAdd) onlyOwner public {
        require(_toAdd != address(0));
        authorized[_toAdd] = true;
        authorizedList.push(_toAdd); //push address in the array of authorized addresses
    }

    function removeAuthorized(address _toRemove) onlyOwner public {
        require(_toRemove != address(0));
        require(_toRemove != msg.sender);
        authorized[_toRemove] = false;
    }

    //experimental added by  Seb
    function removeAllAuthorized() onlyOwner public {
        uint iMax = getNbAuthorizedAddresses();
        for (uint i=0; i<iMax; i++) {authorized[authorizedList[i]] = false;}
        delete authorizedList;
        addAuthorized(msg.sender);
    }
    function getNbAuthorizedAddresses() public view returns(uint count) {
        return authorizedList.length;
    }


}

//Common functions, including the method to create flightId and policyId hashes
contract usingFlyionBasics is Authorizable {

    //Calculation functions
    function createPolicyId(string memory _fltNum, uint256 _depDte, uint _expectedArrDte, uint256 _dlyTime, uint256 _premium, uint _claimPayout, uint256 _expiryDte, uint256 _nbSeatsMax)
    public pure returns (bytes32 ) {
            return keccak256(abi.encodePacked(createFlightId(_fltNum, _depDte), _expectedArrDte, _dlyTime, _premium, _claimPayout, _expiryDte, _nbSeatsMax));
    }
    function createFlightId(string memory _fltNum, uint256 _depDte)
    public pure returns (bytes32) {
      return keccak256(abi.encodePacked(_fltNum, _depDte));
    }

    function updateFlightDelay(uint256 _actualArrDte, uint256 _expectedArrDte) //, uint256 _dlyTime)
    internal pure returns(uint256 _flightDelay, uint8 _fltSts) {

        if(_actualArrDte > _expectedArrDte) {

            _flightDelay = (_actualArrDte - _expectedArrDte);
            _fltSts = 2;

            //define DELAY HERE (_fltSts) ?
        }
        else {_flightDelay = 0; _fltSts = 1;}

    }


    //Token Interactions
    function withdrawTokens(address _tokenAddress, address _recipient)
    public onlyOwner returns (uint256 _withdrawal) {
        _withdrawal = ERC20_Interface(_tokenAddress).balanceOf(address(this));
        ERC20_Interface(_tokenAddress).transfer(_recipient, _withdrawal);
    }
    function _checkTokenBalances(address _tokenAddress)
    public view returns(uint256 _tokenBalance) {
        _tokenBalance = ERC20_Interface(_tokenAddress).balanceOf(address(this));
    }

    //Killswitch
    function _killContract(bool _forceKill, address _tokenAddress)
    public onlyOwner {
        if(_forceKill == false){require(ERC20_Interface(_tokenAddress).balanceOf(address(this)) == 0, "Please withdraw Tokens");} //Require: TOKEN balances = 0
        selfdestruct(msg.sender); //kill
    }

}
