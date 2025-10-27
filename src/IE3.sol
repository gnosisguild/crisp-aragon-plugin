// SPDX-License-Identifier: LGPL-3.0-only
//
// This file is provided WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.
pragma solidity >=0.8.27;

interface IInputValidator {
    /// @notice This function should be called by the Enclave contract to validate the
    /// input of a computation.
    /// @param sender The account that is submitting the input.
    /// @param data The input to be verified.
    /// @return input The decoded, policy-approved application payload.
    function validate(address sender, bytes memory data) external returns (bytes memory input);
}

interface IE3Program {
    /// @notice This function should be called by the Enclave contract to validate the computation parameters.
    /// @param e3Id ID of the E3.
    /// @param seed Seed for the computation.
    /// @param e3ProgramParams ABI encoded computation parameters.
    /// @param computeProviderParams ABI encoded compute provider parameters.
    /// @return encryptionSchemeId ID of the encryption scheme to be used for the computation.
    /// @return inputValidator The input validator to be used for the computation.
    function validate(uint256 e3Id, uint256 seed, bytes calldata e3ProgramParams, bytes calldata computeProviderParams)
        external
        returns (bytes32 encryptionSchemeId, IInputValidator inputValidator);

    /// @notice This function should be called by the Enclave contract to verify the decrypted output of an E3.
    /// @param e3Id ID of the E3.
    /// @param ciphertextOutputHash The keccak256 hash of output data to be verified.
    /// @param proof ABI encoded data to verify the ciphertextOutputHash.
    /// @return success Whether the output data is valid.
    function verify(uint256 e3Id, bytes32 ciphertextOutputHash, bytes memory proof) external returns (bool success);
}

interface IDecryptionVerifier {
    /// @notice This function should be called by the Enclave contract to verify the
    /// decryption of output of a computation.
    /// @param e3Id ID of the E3.
    /// @param plaintextOutputHash The keccak256 hash of the plaintext output to be verified.
    /// @param proof ABI encoded proof of the given output hash.
    /// @return success Whether or not the plaintextOutputHash was successfully verified.
    function verify(uint256 e3Id, bytes32 plaintextOutputHash, bytes memory proof)
        external
        view
        returns (bool success);
}

/// @title E3 struct
/// @notice This struct represents an E3 computation.
/// @param threshold M/N threshold for the committee.
/// @param requestBlock Block number when the E3 was requested.
/// @param startWindow Start window for the computation: index zero is minimum, index 1 is the maxium.
/// @param duration Duration of the E3.
/// @param expiration Timestamp when committee duties expire.
/// @param e3Program Address of the E3 Program contract.
/// @param e3ProgramParams ABI encoded computation parameters.
/// @param customParams Arbitrary ABI-encoded application-defined parameters.
/// @param computeProvider Address of the compute provider contract.
/// @param inputValidator Address of the input validator contract.
/// @param decryptionVerifier Address of the output verifier contract.
/// @param committeeId ID of the selected committee.
/// @param ciphertextOutput Encrypted output data.
/// @param plaintextOutput Decrypted output data.
struct E3 {
    uint256 seed;
    uint32[2] threshold;
    uint256 requestBlock;
    uint256[2] startWindow;
    uint256 duration;
    uint256 expiration;
    bytes32 encryptionSchemeId;
    IE3Program e3Program;
    bytes e3ProgramParams;
    bytes customParams;
    IInputValidator inputValidator;
    IDecryptionVerifier decryptionVerifier;
    bytes32 committeePublicKey;
    bytes32 ciphertextOutput;
    bytes plaintextOutput;
}
