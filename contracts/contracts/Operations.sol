pragma solidity 0.5.16;

import "./Bytes.sol";


/// @title zkSync operations tools
library Operations {

    // Circuit ops and their pubdata (chunks * bytes)

    /// @notice zkSync circuit operation type
    enum OpType {
        Noop,
        Deposit,
        TransferToNew,
        PartialExit,
        CloseAccount,
        Transfer,
        FullExit,
        ChangePubKey
    }

    // Byte lengths

    uint8 constant TOKEN_BYTES = 2;

    uint8 constant PUBKEY_BYTES = 32;

    uint8 constant NONCE_BYTES = 4;

    uint8 constant PUBKEY_HASH_BYTES = 20;

    uint8 constant ADDRESS_BYTES = 20;

    /// @notice Packed fee bytes lengths
    uint8 constant FEE_BYTES = 2;

    /// @notice zkSync account id bytes lengths
    uint8 constant ACCOUNT_ID_BYTES = 3;

    uint8 constant AMOUNT_BYTES = 16;

    /// @notice Signature (for example full exit signature) bytes length
    uint8 constant SIGNATURE_BYTES = 64;

    // Deposit pubdata

    struct Deposit {
        uint24 accountId;
        uint16 tokenId;
        uint128 amount; 
        address owner;
    }

    uint public constant PACKED_DEPOSIT_PUBDATA_BYTES = 
        ACCOUNT_ID_BYTES + TOKEN_BYTES + AMOUNT_BYTES + ADDRESS_BYTES;

    /// Deserialize deposit pubdata
    function readDepositPubdata(bytes memory _data) internal pure
        returns (Deposit memory parsed)
    {
        uint offset = 0;
        (offset, parsed.accountId) = Bytes.readUInt24(_data, offset); // accountId
        (offset, parsed.tokenId) = Bytes.readUInt16(_data, offset);   // tokenId
        (offset, parsed.amount) = Bytes.readUInt128(_data, offset);   // amount
        (offset, parsed.owner) = Bytes.readAddress(_data, offset);    // owner
    }

    /// Serialize deposit pubdata
    function writeDepositPubdata(Deposit memory op) internal pure returns (bytes memory buf) {
        buf = abi.encodePacked(
            new bytes(ACCOUNT_ID_BYTES),          // accountId (ignored)
            Bytes.toBytesFromUInt16(op.tokenId),  // tokenId
            Bytes.toBytesFromUInt128(op.amount),  // amount
            Bytes.toBytesFromAddress(op.owner)    // owner
        );
    }

    /// @notice Check that deposit pubdata from request and block matches
    function depositPubdataMatch(bytes memory _lhs, bytes memory _rhs) internal pure returns (bool) {
        // We must ignore `accountId` because it is present in block pubdata but not in priority queue
        bytes memory lhs_trimmed = Bytes.slice(_lhs, ACCOUNT_ID_BYTES, PACKED_DEPOSIT_PUBDATA_BYTES - ACCOUNT_ID_BYTES);
        bytes memory rhs_trimmed = Bytes.slice(_rhs, ACCOUNT_ID_BYTES, PACKED_DEPOSIT_PUBDATA_BYTES - ACCOUNT_ID_BYTES);
        return keccak256(lhs_trimmed) == keccak256(rhs_trimmed);
    }

    // FullExit pubdata

    struct FullExit {
        uint24 accountId;
        address owner;
        uint16 tokenId;
        uint128 amount;
    }

    uint public constant PACKED_FULL_EXIT_PUBDATA_BYTES = 
        ACCOUNT_ID_BYTES + ADDRESS_BYTES + TOKEN_BYTES + AMOUNT_BYTES;

    function readFullExitPubdata(bytes memory _data) internal pure
        returns (FullExit memory parsed)
    {
        uint offset = 0;
        (offset, parsed.accountId) = Bytes.readUInt24(_data, offset);      // accountId
        (offset, parsed.owner) = Bytes.readAddress(_data, offset);         // owner
        (offset, parsed.tokenId) = Bytes.readUInt16(_data, offset);        // tokenId
        (offset, parsed.amount) = Bytes.readUInt128(_data, offset);        // amount
    }

    function writeFullExitPubdata(FullExit memory op) internal pure returns (bytes memory buf) {
        buf = abi.encodePacked(
            Bytes.toBytesFromUInt24(op.accountId),  // accountId
            Bytes.toBytesFromAddress(op.owner),     // owner
            Bytes.toBytesFromUInt16(op.tokenId),    // tokenId
            Bytes.toBytesFromUInt128(op.amount)     // amount
        );
    }

    /// @notice Check that full exit pubdata from request and block matches
    function fullExitPubdataMatch(bytes memory _lhs, bytes memory _rhs) internal pure returns (bool) {
        // We must ignore `amount` because it is present in block pubdata but not in priority queue
        bytes memory lhs_trimmed = Bytes.slice(_lhs, 0, PACKED_FULL_EXIT_PUBDATA_BYTES - AMOUNT_BYTES);
        bytes memory rhs_trimmed = Bytes.slice(_rhs, 0, PACKED_FULL_EXIT_PUBDATA_BYTES - AMOUNT_BYTES);
        return keccak256(lhs_trimmed) == keccak256(rhs_trimmed);
    }

    // PartialExit pubdata
    
    struct PartialExit {
        //uint24 accountId;
        uint16 tokenId;
        uint128 amount;
        //uint16 fee;
        address owner;
    }

    function readPartialExitPubdata(bytes memory _data, uint _offset) internal pure
        returns (PartialExit memory parsed)
    {
        uint offset = _offset + ACCOUNT_ID_BYTES;                   // accountId (ignored)
        (offset, parsed.tokenId) = Bytes.readUInt16(_data, offset); // tokenId
        (offset, parsed.amount) = Bytes.readUInt128(_data, offset); // amount
        offset += FEE_BYTES;                                        // fee (ignored)
        (offset, parsed.owner) = Bytes.readAddress(_data, offset);  // owner
    }

    function writePartialExitPubdata(PartialExit memory op) internal pure returns (bytes memory buf) {
        buf = abi.encodePacked(
            new bytes(ACCOUNT_ID_BYTES),          // accountId (ignored)
            Bytes.toBytesFromUInt16(op.tokenId),  // tokenId
            Bytes.toBytesFromUInt128(op.amount),  // amount
            new bytes(FEE_BYTES),                 // fee (ignored)
            Bytes.toBytesFromAddress(op.owner)    // owner
        );
    }

    // ChangePubKey

    struct ChangePubKey {
        // uint24 accountId;
        bytes pubKeyHash;
        address owner;
        uint32 nonce;
    }

    function readChangePubKeyPubdata(bytes memory _data, uint _offset) internal pure
        returns (ChangePubKey memory parsed)
    {
        uint offset = _offset + ACCOUNT_ID_BYTES;                                    // accountId (ignored)
        (offset, parsed.pubKeyHash) = Bytes.read(_data, offset, PUBKEY_HASH_BYTES);  // pubKeyHash
        (offset, parsed.owner) = Bytes.readAddress(_data, offset);                   // owner
        (offset, parsed.nonce) = Bytes.readUInt32(_data, offset);                    // nonce
    }

    // Withdrawal data process

    function readWithdrawalData(bytes memory _data, uint _offset) internal pure
        returns (bool _addToPendingWithdrawalsQueue, address _to, uint16 _tokenId, uint128 _amount)
    {
        uint offset = _offset;
        (offset, _addToPendingWithdrawalsQueue) = Bytes.readBool(_data, offset);
        (offset, _to) = Bytes.readAddress(_data, offset);
        (offset, _tokenId) = Bytes.readUInt16(_data, offset);
        (offset, _amount) = Bytes.readUInt128(_data, offset);
    }

}
