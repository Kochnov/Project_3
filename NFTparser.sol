pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";




contract NFTParser is ERC721Holder, Ownable {
    using Strings for uint256;

    string private _openSeaBaseUrl = "https://opensea.io/assets/";
    string private _blurBaseUrl = "https://blur.network/nfts/";

    address private _ganacheAddress = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
    AggregatorV3Interface private _priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    address private _openSeaRegistryAddress;

    constructor(address openSeaRegistryAddress) {
        _openSeaRegistryAddress = openSeaRegistryAddress;
    }

function getNFTName(IERC721 nftContract, uint256 tokenId) private view returns (string memory) {
        try nftContract.name() returns (string memory name) {
            return name;
        } catch {
            try nftContract.symbol() returns (string memory symbol) {
                return symbol;
            } catch {
                revert("Failed to get NFT name");
            }
        }
    }

function getNFTSymbol(IERC721 nftContract) private view returns (string memory) {
        try nftContract.symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            try nftContract.name() returns (string memory name) {
                return name;
            } catch {
                revert("Failed to get NFT symbol");
            }
        }
    }

function getNFTDetails(string memory openseaUrl, string memory blurUrl) external view returns (string memory, string memory, uint256) {
        (string memory openseaName, string memory openseaSymbol, uint256 openseaPrice) = getNFTDetailsFromOpenSea(openseaUrl, _openSeaRegistryAddress);
        (string memory blurName, string memory blurSymbol, uint256 blurPrice) = getNFTDetailsFromBlur(blurUrl);
        if (openseaPrice > blurPrice) {
            return (openseaName, openseaSymbol, openseaPrice);
        } else {
            return (blurName, blurSymbol, blurPrice);
        }
    }

function getOpenSeaAssetId(string memory url) public pure returns (uint256) {
    // Example URL: https://opensea.io/assets/0x06012c8cf97bead5deae237070f9587f8e7a266d/72148234843192391262091434786581796622320043564512629596459416874641653210115
    uint256 start = bytes(_openSeaBaseUrl).length;
    uint256 end = bytes(url).length - 1;
    require(startsWith(url, _openSeaBaseUrl, 0), "Invalid URL");
    string memory assetIdStr = substring(url, start, end);
    bytes memory assetIdBytes = bytes(assetIdStr);
    uint256 assetId = 0;
    for (uint256 i = 0; i < assetIdBytes.length; i++) {
        require(assetIdBytes[i] >= 48 && assetIdBytes[i] <= 57, "Invalid asset ID");
        assetId = assetId * 10 + (uint256(assetIdBytes[i]) - 48);
    }
    return assetId;
}

function getNFTDetailsFromOpenSea(string memory url, address openSeaRegistryAddress) public view returns (string memory, string memory, uint256) {
    IERC721 nftContract = IERC721(getNFTAddress(url));
    uint256 tokenId = nftContract.tokenOfOwnerByIndex(address(this), 0); // assuming you want the first token owned by the contract
    string memory name = getNFTName(nftContract, tokenId);
    string memory symbol = getNFTSymbol(nftContract);
    address openSeaRegistryAddress = 0xa5409ec958c83c3f309868babaca7c86dcb077c1; // replace with actual OpenSea registry address
    (uint256 price,,,,,) = IOpenSeaRegistry(openSeaRegistryAddress).assets(getOpenSeaAssetId(url)).current;
    return (name, symbol, price);
}

function getNFTPriceFromBlur(string memory url) public view returns (uint256) {
    // Example URL: https://blur.network/nfts/11
    (uint256 start, uint256 end) = indexOf("/nfts/", url, 0, bytes(url).length - 1);
    require(end < bytes(url).length - 1, "Invalid URL");
    start = end + 1;
    end = indexOf("/", url, start, bytes(url).length - 1) - 1;
    string memory tokenIdStr = substring(url, start, end);
    bytes memory tokenIdBytes = bytes(tokenIdStr);
    uint256 tokenId = 0;
    for (uint256 i = 0; i < tokenIdBytes.length; i++) {
        uint8 digit = uint8(tokenIdBytes[i]);
        require(digit >= 48 && digit <= 57, "Invalid token ID");
        tokenId = tokenId * 10 + (uint256(digit) - 48);
    }
    string memory apiUrl = string(abi.encodePacked("https://api.blur.network/nfts/", tokenIdStr));
    string memory responseBody = "";
    (bool success, bytes memory data) = address(this).staticcall(abi.encodeWithSelector(bytes4(keccak256("httpGet(string)")), apiUrl));
    if (success) {
        responseBody = abi.decode(data, (string));
    } else {
        revert("Failed to get NFT price from Blur");
    }
    string[] memory parts = responseBody.split(":");
    require(parts.length == 2, "Invalid API response");
    uint256 price = parseFixedPoint(parts[1]);
    return price;
}


function parseFixedPoint(string memory value) private pure returns (uint256) {
    bytes memory valueBytes = bytes(value);
    uint256 integerPart = 0;
    uint256 fractionalPart = 0;
    uint256 divisor = 1;
    bool readingFractionalPart = false;
    for (uint256 i = 0; i < valueBytes.length; i++) {
        uint8 digit = uint8(valueBytes[i]);
        if (digit >= 48 && digit <= 57) {
            if (readingFractionalPart) {
                fractionalPart = fractionalPart * 10 + (uint256(digit) - 48);
                divisor *= 10;
            } else {
                integerPart = integerPart * 10 + (uint256(digit) - 48);
            }
        } else if (digit == 46) {
            readingFractionalPart = true;
        } else {
            revert("Invalid fixed-point value");
        }
    }
    return integerPart * divisor + fractionalPart;
}

function getNFTDetailsFromBlur(string memory url) public view returns (string memory, string memory, uint256) {
    IERC721 nftContract = IERC721(getNFTAddress(url));
    uint256 tokenId = getNFTTokenIdFromBlur(url);
    string memory name = getNFTName(nftContract, tokenId);
    string memory symbol = getNFTSymbol(nftContract);
    uint256 price = getNFTPriceFromBlur(url);
    return (name, symbol, price);
}
function getNFTSymbol(IERC721 nftContract) private view returns (string memory) {
        try nftContract.symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            try nftContract.name() returns (string memory name) {
                return name;
            } catch {
                revert("Failed to get NFT symbol");
            }
        }
    }


function getNFTDetailsFromBlur(string memory url) public view returns (string memory, string memory, uint256) {
    IERC721 nftContract = IERC721(getNFTAddress(url));
    uint256 tokenId = getNFTTokenIdFromBlur(url);
    string memory name = getNFTName(nftContract, tokenId);
    string memory symbol = getNFTSymbol(nftContract);
    uint256 price = getNFTPriceFromBlur(url);
    return (name, symbol, price);
}

function startsWith(string memory _str, string memory _prefix, uint256 _offset) internal pure returns (bool) {
    bytes memory str = bytes(_str);
    bytes memory prefix = bytes(_prefix);
    if (str.length - _offset < prefix.length) {
        return false;
    }
    for (uint256 i = 0; i < prefix.length; i++) {
        if (str[_offset + i] != prefix[i]) {
            return false;
        }
    }
    return true;
}

function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
    bytes memory strBytes = bytes(str);
    require(startIndex <= endIndex && endIndex < strBytes.length, "Invalid substring range");
    bytes memory result = new bytes(endIndex - startIndex + 1);
    for (uint i = startIndex; i <= endIndex; i++) {
        result[i - startIndex] = strBytes[i];
    }
    return string(result);
}

function getNFTTokenIdFromBlur(string memory url) public view returns (uint256) {
    // Example URL: https://blur.network/nfts/11
    uint256 start = 0;
    uint256 end = bytes(_blurBaseUrl).length - 1;
    require(startsWith(url, _blurBaseUrl, start), "Invalid URL");
    string memory tokenIdStr = substring(url, end, bytes(url).length - end);
    bytes memory tokenIdBytes = bytes(tokenIdStr);
    require(tokenIdBytes.length > 0, "Invalid token ID");
    uint256 tokenId = 0;
    for (uint256 i = 0; i < tokenIdBytes.length; i++) {
        uint8 digit = uint8(tokenIdBytes[i]);
        require(digit >= 48 && digit <= 57, "Invalid token ID");
        tokenId = tokenId * 10 + (uint256(digit) - 48);
    }
    return tokenId;
}

function indexOf(string memory needle, string memory haystack, uint256 start, uint256 end) internal pure returns (uint256, uint256) {
    uint256 hIndex = start;
    uint256 nIndex = 0;
    while (hIndex <= end && nIndex < bytes(needle).length) {
        if (bytes(haystack)[hIndex] == bytes(needle)[nIndex]) {
            nIndex++;
        } else {
            hIndex = hIndex - nIndex;
            nIndex = 0;
        }
        hIndex++;
    }
    require(nIndex == bytes(needle).length, "Needle not found");
    return (hIndex - nIndex, hIndex - 1);
}

function hexStringToBytes(string memory hexString) internal pure returns (bytes memory) {
    uint256 len = bytes(hexString).length;
    require(len % 2 == 0, "hexStringToBytes: invalid string length");
    bytes memory bytesArray = new bytes(len / 2);
    for (uint256 i = 0; i < len; i += 2) {
        uint256 x = uint256(hexCharToUint(bytes(hexString)[i])) * 16 + uint256(hexCharToUint(bytes(hexString)[i + 1]));
        bytesArray[i / 2] = bytes1(uint8(x));
    }
    return bytesArray;
}
//The byte type can only be used for a single byte (8 bits), not for arrays of bytes. Instead, we define the bytesArray as a bytes memory array and use the push method to append each byte to it.
function hexCharToUint(bytes1 c) private pure returns (uint8) {
    if (c >= bytes1("0") && c <= bytes1("9")) {
        return uint8(c) - uint8(bytes1("0"));
    }
    if (c >= bytes1("a") && c <= bytes1("f")) {
        return uint8(c) - uint8(bytes1("a")) + 10;
    }
    if (c >= bytes1("A") && c <= bytes1("F")) {
        return uint8(c) - uint8(bytes1("A")) + 10;
    }
    revert("hexCharToUint: invalid character");
}


function hexCharToByte(bytes1 c) private pure returns (uint8) {
    if (uint8(c) >= uint8(bytes1("0")) && uint8(c) <= uint8(bytes1("9"))) {
        return uint8(c) - uint8(bytes1("0"));
    } else if (uint8(c) >= uint8(bytes1("a")) && uint8(c) <= uint8(bytes1("f"))) {
        return uint8(c) - uint8(bytes1("a")) + 10;
    } else if (uint8(c) >= uint8(bytes1("A")) && uint8(c) <= uint8(bytes1("F"))) {
        return uint8(c) - uint8(bytes1("A")) + 10;
    } else {
        revert("hexCharToByte: invalid hex char");
    }
}


function getNFTAddress(string memory url) public pure returns (address) {
    uint256 start = 0;
    uint256 end = bytes(_openSeaBaseUrl).length - 1;
    if (startsWith(_openSeaBaseUrl, url, start)) {
        (start, end) = indexOf("/assets/", url, start, end);
        start += 8;
        end = indexOf("/", url, start, end) - 1;
        bytes memory addressBytes = hexStringToBytes(substring(url, start, end));
        require(addressBytes.length == 20, "Invalid address length");
        address nftAddress = address(uint160(uint256(keccak256(addressBytes))));
        return nftAddress;
    } else if (startsWith(_blurBaseUrl, url, start)) {
        (start, end) = indexOf("nfts/", url, start, end);
        start += 5;
        end = indexOf("/", url, start, end) - 1;
        bytes memory addressBytes = hexStringToBytes(substring(url, start, end));
        require(addressBytes.length == 20, "Invalid address length");
        address nftAddress = address(uint160(uint256(keccak256(addressBytes))));
        return nftAddress;
    } else {
        revert("Invalid URL");
    }
}

function convertToEth(uint256 price) private view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331); // price feed for ETH/USD on mainnet
    (, int256 answer, , , ) = priceFeed.latestRoundData();
    uint256 ethPriceInUsd = uint256(answer);
    return price * 1e18 / ethPriceInUsd;
}

function buyCheapestNFT(string memory openseaUrl, string memory blurUrl) external {
        // Get NFT details from OpenSea and Blur
        (string memory openseaName, string memory openseaSymbol, uint256 openseaPrice) = getNFTDetailsFromOpenSea(openseaUrl);
        (string memory blurName, string memory blurSymbol, uint256 blurPrice) = getNFTDetailsFromBlur(blurUrl);

        // Determine which NFT is cheaper
        if (blurPrice < convertToEth(openseaPrice)) {
            // Buy NFT from Blur
            buyNFTFromBlur(blurUrl);
        } else {
            // Buy NFT from OpenSea
            buyNFTFromOpenSea(openseaUrl);
        }
    }

function buyNFTFromBlur(string memory url) private {
        // Get NFT details
        IERC721 nftContract = IERC721(getNFTAddress(url));
        uint256 tokenId = getNFTTokenIdFromBlur(url);

        // Approve NFT transfer
        nftContract.approve(address(this), tokenId);

        // Buy NFT
        try nftContract.safeTransferFrom(address(this), _ganacheAddress, tokenId) {
            console.log("Successfully bought NFT from Blur");
        } catch {
            console.log("Failed to buy NFT from Blur");
            revert("Failed to buy NFT from Blur");
        }
    }

function getNFTTokenId(string memory url) private pure returns (uint256) {
    // Example URL: https://opensea.io/assets/0x06012c8cf97bead5deae237070f9587f8e7a266d/72148234843192391262091434786581796622320043564512629596459416874641653210115
    uint256 start = bytes(_openSeaBaseUrl).length;
    uint256 end = bytes(url).length - 1;
    require(startsWith(url, _openSeaBaseUrl, 0), "Invalid URL");
    string memory tokenIdStr = substring(url, start, end);
    bytes memory tokenIdBytes = bytes(tokenIdStr);
    uint256 tokenId = 0;
    for (uint256 i = 0; i < tokenIdBytes.length; i++) {
        require(tokenIdBytes[i] >= 48 && tokenIdBytes[i] <= 57, "Invalid token ID");
        tokenId = tokenId * 10 + (uint256(tokenIdBytes[i]) - 48);
    }
    return tokenId;
}

function buyNFTFromOpenSea(string memory url) private {
        // Get NFT details
        IERC721 nftContract = IERC721(getNFTAddress(url));
        uint256 tokenId = getNFTTokenId(url);

        // Approve NFT transfer
        nftContract.approve(address(this), tokenId);

        // Buy NFT
        try nftContract.safeTransferFrom(address(this), _ganacheAddress, tokenId) {
            console.log("Successfully bought NFT from OpenSea");
        } catch {
            console.log("Failed to buy NFT from OpenSea");
            revert("Failed to buy NFT from OpenSea");
        }
    }
}