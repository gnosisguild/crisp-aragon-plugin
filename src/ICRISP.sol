// SPDX-License-Identifier: LGPL-3.0-only
//
// This file is provided WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.

/// @title ICRISP
interface ICRISP {
    /// @notice Decode the tally for a given e3Id
    /// @param e3Id The identifier for the e3 instance
    /// @return yes The number of 'yes' votes
    /// @return no The number of 'no' votes
    function decodeTally(uint256 e3Id) external view returns (uint256 yes, uint256 no);
}
