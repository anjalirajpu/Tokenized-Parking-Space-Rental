// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Tokenized Parking Space Rental
 * @dev A smart contract for tokenizing parking spaces and managing rentals
 */
contract TokenizedParkingSpaceRental is ERC721, Ownable, ReentrancyGuard {
    
    // Struct to represent a parking space
    struct ParkingSpace {
        uint256 id;
        string location;
        uint256 pricePerHour; // Price in wei
        address owner;
        bool isAvailable;
        bool exists;
    }
    
    // Struct to represent a rental
    struct Rental {
        uint256 spaceId;
        address renter;
        uint256 startTime;
        uint256 endTime;
        uint256 totalCost;
        bool isActive;
    }
    
    // State variables
    uint256 private _nextTokenId = 1;
    uint256 private _nextRentalId = 1;
    
    // Mappings
    mapping(uint256 => ParkingSpace) public parkingSpaces;
    mapping(uint256 => Rental) public rentals;
    mapping(uint256 => uint256[]) public spaceToRentals; // spaceId => rentalIds[]
    mapping(address => uint256[]) public userRentals; // user => rentalIds[]
    
    // Events
    event ParkingSpaceCreated(uint256 indexed spaceId, string location, uint256 pricePerHour, address indexed owner);
    event SpaceRented(uint256 indexed rentalId, uint256 indexed spaceId, address indexed renter, uint256 startTime, uint256 endTime, uint256 totalCost);
    event RentalCompleted(uint256 indexed rentalId, uint256 indexed spaceId);
    event PriceUpdated(uint256 indexed spaceId, uint256 newPrice);
    
    constructor() ERC721("ParkingSpaceToken", "PST") {}
    
    /**
     * @dev Core Function 1: Create and tokenize a parking space
     * @param location The location description of the parking space
     * @param pricePerHour The hourly rental price in wei
     */
    function createParkingSpace(string memory location, uint256 pricePerHour) 
        external 
        returns (uint256) 
    {
        require(bytes(location).length > 0, "Location cannot be empty");
        require(pricePerHour > 0, "Price must be greater than 0");
        
        uint256 spaceId = _nextTokenId;
        _nextTokenId++;
        
        // Create the parking space
        parkingSpaces[spaceId] = ParkingSpace({
            id: spaceId,
            location: location,
            pricePerHour: pricePerHour,
            owner: msg.sender,
            isAvailable: true,
            exists: true
        });
        
        // Mint NFT to represent ownership
        _safeMint(msg.sender, spaceId);
        
        emit ParkingSpaceCreated(spaceId, location, pricePerHour, msg.sender);
        
        return spaceId;
    }
    
    /**
     * @dev Core Function 2: Rent a parking space for specified duration
     * @param spaceId The ID of the parking space to rent
     * @param durationHours The rental duration in hours
     */
    function rentParkingSpace(uint256 spaceId, uint256 durationHours) 
        external 
        payable 
        nonReentrant 
        returns (uint256) 
    {
        require(parkingSpaces[spaceId].exists, "Parking space does not exist");
        require(parkingSpaces[spaceId].isAvailable, "Parking space is not available");
        require(durationHours > 0, "Duration must be greater than 0");
        require(durationHours <= 24, "Maximum rental duration is 24 hours");
        
        ParkingSpace storage space = parkingSpaces[spaceId];
        uint256 totalCost = space.pricePerHour * durationHours;
        
        require(msg.value >= totalCost, "Insufficient payment");
        
        uint256 rentalId = _nextRentalId;
        _nextRentalId++;
        
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + (durationHours * 1 hours);
        
        // Create rental record
        rentals[rentalId] = Rental({
            spaceId: spaceId,
            renter: msg.sender,
            startTime: startTime,
            endTime: endTime,
            totalCost: totalCost,
            isActive: true
        });
        
        // Update mappings
        spaceToRentals[spaceId].push(rentalId);
        userRentals[msg.sender].push(rentalId);
        
        // Mark space as unavailable
        space.isAvailable = false;
        
        // Transfer payment to space owner
        payable(space.owner).transfer(totalCost);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        emit SpaceRented(rentalId, spaceId, msg.sender, startTime, endTime, totalCost);
        
        return rentalId;
    }
    
    /**
     * @dev Core Function 3: Complete rental and make space available again
     * @param rentalId The ID of the rental to complete
     */
    function completeRental(uint256 rentalId) external {
        require(rentals[rentalId].renter != address(0), "Rental does not exist");
        require(rentals[rentalId].isActive, "Rental is not active");
        
        Rental storage rental = rentals[rentalId];
        
        // Only the renter or space owner can complete the rental
        require(
            msg.sender == rental.renter || 
            msg.sender == parkingSpaces[rental.spaceId].owner,
            "Not authorized to complete this rental"
        );
        
        // Check if rental period has ended
        require(block.timestamp >= rental.endTime, "Rental period has not ended");
        
        // Mark rental as completed
        rental.isActive = false;
        
        // Make parking space available again
        parkingSpaces[rental.spaceId].isAvailable = true;
        
        emit RentalCompleted(rentalId, rental.spaceId);
    }
    
    // Additional utility functions
    
    /**
     * @dev Update the price of a parking space (only owner)
     * @param spaceId The ID of the parking space
     * @param newPricePerHour The new hourly price in wei
     */
    function updateSpacePrice(uint256 spaceId, uint256 newPricePerHour) external {
        require(parkingSpaces[spaceId].exists, "Parking space does not exist");
        require(ownerOf(spaceId) == msg.sender, "Not the owner of this space");
        require(newPricePerHour > 0, "Price must be greater than 0");
        
        parkingSpaces[spaceId].pricePerHour = newPricePerHour;
        
        emit PriceUpdated(spaceId, newPricePerHour);
    }
    
    /**
     * @dev Get rental history for a parking space
     * @param spaceId The ID of the parking space
     */
    function getSpaceRentals(uint256 spaceId) external view returns (uint256[] memory) {
        return spaceToRentals[spaceId];
    }
    
    /**
     * @dev Get user's rental history
     * @param user The address of the user
     */
    function getUserRentals(address user) external view returns (uint256[] memory) {
        return userRentals[user];
    }
    
    /**
     * @dev Check if a rental is currently active
     * @param rentalId The ID of the rental
     */
    function isRentalActive(uint256 rentalId) external view returns (bool) {
        Rental memory rental = rentals[rentalId];
        return rental.isActive && block.timestamp < rental.endTime;
    }
    
    /**
     * @dev Get available parking spaces (basic implementation)
     * @return An array of available space IDs (limited to first 100 for gas efficiency)
     */
    function getAvailableSpaces() external view returns (uint256[] memory) {
        uint256[] memory tempSpaces = new uint256[](100);
        uint256 count = 0;
        
        for (uint256 i = 1; i < _nextTokenId && count < 100; i++) {
            if (parkingSpaces[i].exists && parkingSpaces[i].isAvailable) {
                tempSpaces[count] = i;
                count++;
            }
        }
        
        // Create array with exact size
        uint256[] memory availableSpaces = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            availableSpaces[i] = tempSpaces[i];
        }
        
        return availableSpaces;
    }
}
