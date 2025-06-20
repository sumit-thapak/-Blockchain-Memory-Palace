// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Blockchain Memory Palace
 * @dev A smart contract that allows users to store encrypted memories tied to physical locations
 * @author Memory Palace Protocol Team
 */
contract Project {
    
    struct Memory {
        address owner;
        string encryptedContent;
        uint256 timestamp;
        int256 latitude;
        int256 longitude;
        uint256 unlockTime;
        address[] inheritanceAddresses;
        bool isPublic;
        uint256 likes;
        string memoryType; // personal, community, historical, etc.
    }
    
    struct Location {
        int256 latitude;
        int256 longitude;
        uint256 memoryCount;
        uint256 communityRating;
        bool isLandmark;
    }
    
    // State variables
    mapping(bytes32 => Memory) public memories;
    mapping(bytes32 => Location) public locations;
    mapping(address => bytes32[]) public userMemories;
    mapping(address => uint256) public userReputation;
    
    bytes32[] public allMemoryIds;
    bytes32[] public landmarkLocations;
    
    uint256 public totalMemories;
    uint256 private constant LOCATION_PRECISION = 1000000; // 6 decimal places
    
    // Events
    event MemoryStored(
        bytes32 indexed memoryId,
        address indexed owner,
        int256 latitude,
        int256 longitude,
        uint256 unlockTime
    );
    
    event MemoryUnlocked(
        bytes32 indexed memoryId,
        address indexed accessor,
        uint256 timestamp
    );
    
    event LocationBecameLandmark(
        bytes32 indexed locationId,
        int256 latitude,
        int256 longitude,
        uint256 memoryCount
    );
    
    event MemoryLiked(
        bytes32 indexed memoryId,
        address indexed liker,
        uint256 totalLikes
    );
    
    // Modifiers
    modifier onlyMemoryOwner(bytes32 _memoryId) {
        require(memories[_memoryId].owner == msg.sender, "Not memory owner");
        _;
    }
    
    modifier memoryExists(bytes32 _memoryId) {
        require(memories[_memoryId].owner != address(0), "Memory does not exist");
        _;
    }
    
    modifier canAccessMemory(bytes32 _memoryId) {
        Memory storage memoryData = memories[_memoryId];
        require(
            memoryData.owner == msg.sender ||
            memoryData.isPublic ||
            block.timestamp >= memoryData.unlockTime ||
            isInheritanceAddress(_memoryId, msg.sender),
            "Cannot access this memory"
        );
        _;
    }
    
    /**
     * @dev Store a new memory at a specific location
     * @param _encryptedContent The encrypted memory content
     * @param _latitude Latitude coordinate (multiplied by LOCATION_PRECISION)
     * @param _longitude Longitude coordinate (multiplied by LOCATION_PRECISION)
     * @param _unlockTime Timestamp when memory becomes accessible to inheritance addresses
     * @param _inheritanceAddresses Addresses that can access memory after unlock time
     * @param _isPublic Whether memory is publicly accessible
     * @param _memoryType Type/category of the memory
     */
    function storeMemory(
        string memory _encryptedContent,
        int256 _latitude,
        int256 _longitude,
        uint256 _unlockTime,
        address[] memory _inheritanceAddresses,
        bool _isPublic,
        string memory _memoryType
    ) external {
        require(bytes(_encryptedContent).length > 0, "Memory content cannot be empty");
        require(_unlockTime > block.timestamp, "Unlock time must be in future");
        
        // Generate unique memory ID
        bytes32 memoryId = keccak256(
            abi.encodePacked(
                msg.sender,
                _latitude,
                _longitude,
                block.timestamp,
                totalMemories
            )
        );
        
        // Generate location ID
        bytes32 locationId = keccak256(abi.encodePacked(_latitude, _longitude));
        
        // Store memory
        memories[memoryId] = Memory({
            owner: msg.sender,
            encryptedContent: _encryptedContent,
            timestamp: block.timestamp,
            latitude: _latitude,
            longitude: _longitude,
            unlockTime: _unlockTime,
            inheritanceAddresses: _inheritanceAddresses,
            isPublic: _isPublic,
            likes: 0,
            memoryType: _memoryType
        });
        
        // Update location data
        locations[locationId].latitude = _latitude;
        locations[locationId].longitude = _longitude;
        locations[locationId].memoryCount++;
        
        // Check if location should become a landmark (5+ memories)
        if (locations[locationId].memoryCount >= 5 && !locations[locationId].isLandmark) {
            locations[locationId].isLandmark = true;
            landmarkLocations.push(locationId);
            emit LocationBecameLandmark(locationId, _latitude, _longitude, locations[locationId].memoryCount);
        }
        
        // Update user data
        userMemories[msg.sender].push(memoryId);
        userReputation[msg.sender] += 10; // Reward for contributing
        
        // Update global state
        allMemoryIds.push(memoryId);
        totalMemories++;
        
        emit MemoryStored(memoryId, msg.sender, _latitude, _longitude, _unlockTime);
    }
    
    /**
     * @dev Retrieve a memory (if accessible)
     * @param _memoryId The ID of the memory to retrieve
     * @return owner Address of the memory owner
     * @return encryptedContent The encrypted memory content
     * @return timestamp When the memory was created
     * @return latitude Latitude coordinate of the memory location
     * @return longitude Longitude coordinate of the memory location
     * @return memoryType Type/category of the memory
     * @return likes Number of likes the memory has received
     */
    function retrieveMemory(bytes32 _memoryId) 
        external 
        memoryExists(_memoryId)
        canAccessMemory(_memoryId)
        returns (
            address owner,
            string memory encryptedContent,
            uint256 timestamp,
            int256 latitude,
            int256 longitude,
            string memory memoryType,
            uint256 likes
        ) 
    {
        Memory storage memoryData = memories[_memoryId];
        
        // Increase reputation for memory owner when accessed
        if (memoryData.owner != msg.sender) {
            userReputation[memoryData.owner] += 1;
        }
        
        emit MemoryUnlocked(_memoryId, msg.sender, block.timestamp);
        
        return (
            memoryData.owner,
            memoryData.encryptedContent,
            memoryData.timestamp,
            memoryData.latitude,
            memoryData.longitude,
            memoryData.memoryType,
            memoryData.likes
        );
    }
    
    /**
     * @dev Explore memories at a specific location within a radius
     * @param _latitude Center latitude for search
     * @param _longitude Center longitude for search
     * @param _radiusKm Search radius in kilometers (multiplied by 1000)
     * @return Array of accessible memory IDs in the area
     */
    function exploreLocation(
        int256 _latitude,
        int256 _longitude,
        uint256 _radiusKm
    ) external view returns (bytes32[] memory) {
        bytes32[] memory nearbyMemories = new bytes32[](totalMemories);
        uint256 count = 0;
        
        for (uint256 i = 0; i < allMemoryIds.length; i++) {
            bytes32 memoryId = allMemoryIds[i];
            Memory storage memoryData = memories[memoryId];
            
            // Check if memory is accessible
            if (!isMemoryAccessible(memoryId, msg.sender)) {
                continue;
            }
            
            // Calculate distance (simplified - for production use proper haversine formula)
            int256 latDiff = memoryData.latitude - _latitude;
            int256 lonDiff = memoryData.longitude - _longitude;
            uint256 distanceSquared = uint256(latDiff * latDiff + lonDiff * lonDiff);
            uint256 radiusSquared = (_radiusKm * 1000 * LOCATION_PRECISION / 111) ** 2; // Rough conversion
            
            if (distanceSquared <= radiusSquared) {
                nearbyMemories[count] = memoryId;
                count++;
            }
        }
        
        // Trim array to actual size
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = nearbyMemories[i];
        }
        
        return result;
    }
    
    /**
     * @dev Like a public memory
     * @param _memoryId The ID of the memory to like
     */
    function likeMemory(bytes32 _memoryId) external memoryExists(_memoryId) {
        require(memories[_memoryId].isPublic, "Can only like public memories");
        require(memories[_memoryId].owner != msg.sender, "Cannot like own memory");
        
        memories[_memoryId].likes++;
        userReputation[memories[_memoryId].owner] += 5; // Reward memory owner
        
        emit MemoryLiked(_memoryId, msg.sender, memories[_memoryId].likes);
    }
    
    // Helper functions
    function isInheritanceAddress(bytes32 _memoryId, address _address) internal view returns (bool) {
        address[] storage inheritanceAddresses = memories[_memoryId].inheritanceAddresses;
        for (uint256 i = 0; i < inheritanceAddresses.length; i++) {
            if (inheritanceAddresses[i] == _address) {
                return true;
            }
        }
        return false;
    }
    
    function isMemoryAccessible(bytes32 _memoryId, address _user) internal view returns (bool) {
        Memory storage memoryData = memories[_memoryId];
        return (
            memoryData.owner == _user ||
            memoryData.isPublic ||
            block.timestamp >= memoryData.unlockTime ||
            isInheritanceAddress(_memoryId, _user)
        );
    }
    
    // View functions
    function getUserMemoryCount(address _user) external view returns (uint256) {
        return userMemories[_user].length;
    }
    
    function getLandmarkCount() external view returns (uint256) {
        return landmarkLocations.length;
    }
    
    function getLocationMemoryCount(int256 _latitude, int256 _longitude) external view returns (uint256) {
        bytes32 locationId = keccak256(abi.encodePacked(_latitude, _longitude));
        return locations[locationId].memoryCount;
    }
}
