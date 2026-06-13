package main

import (
	"archive/zip"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

func main() {

	author := flag.String("author", "", "specifies the author of the bundle")
	pkFilename := flag.String("pk-file", "", "specifies the private key file")
	inBnFilename := flag.String("input-bundle", "", "specifies the input bundle directory")
	useNokiaRDKey := flag.Bool("use-nokia-rd-key", false, "specifies if generated artifact to be signed by Nokia R&D Key")
	unsigned := flag.Bool("unsigned", false, "specifies if generated artifact to be unsigned")
	corruptedCheckSum := flag.Bool("corrupted-cksum", false, "specifies if generated artifact should have corrupted checksum, this is used for negative testing")
	version := flag.String("version", "", "specifies the version of the bundle")

	flag.Parse()

	if *inBnFilename == "" {
		fmt.Println("input bundle directory (input-bundle) is need to generate artifact bundle")
		//flag.PrintDefaults()
		return
	}

	if !*useNokiaRDKey && !*unsigned && (*author == "" || *pkFilename == "") {
		fmt.Println("author and private key file (pk-file) is needed to generate signed artifact")
		//flag.PrintDefaults()
		return
	}

	log.Println("Parsing the metadata.json content")
	//opening metadata json file
	inMetaJson, err := os.Open(*inBnFilename + "/metadata.json")
	defer inMetaJson.Close()
	if err != nil {
		log.Println("Error occurred during opening the metadata.json file")
		log.Fatal(err)
		return
	}

	//reading metadata content
	fileData, err := ioutil.ReadAll(inMetaJson)
	if err != nil {
		log.Println("Error occurred during reading the metadata.json file")
		log.Fatal(err)
		return
	}

	var metadata Meta
	if err := json.Unmarshal(fileData, &metadata); err != nil {
		log.Println("Error occurred while parsing the json")
		log.Fatal(err)
		return
	}

	log.Println("Updating content info in the metadata.json")
	//update the createBy and Creation Date
	metadata.CreationDate = time.Now().Format(time.RFC1123)
	if *useNokiaRDKey {
		metadata.CreatedBy = "NOKIARND"
	} else {
		metadata.CreatedBy = *author //hard-coded for now
	}

	// Create a file to write the archive buffer to
	// Could also use an in memory buffer.
	name := metadata.Name
	if name == "" {
		_, name = filepath.Split(*inBnFilename)
	}
	if *version != "" {
		metadata.Version = *version
	}

	generatedBundleName := name + "-" + metadata.Version + ".zip"
	var validationResult = IsQualifiedName(generatedBundleName)
	if len(validationResult) <=0 {
		log.Println(generatedBundleName + " is a valid name for a bundle.")

	} else {
		log.Println(generatedBundleName + " is not a valid name for a bundle. Bundle name should be a valid dns value.")
		log.Println(validationResult)
		return
	}
	outFile, err := os.Create(generatedBundleName)
	if err != nil {
		log.Fatal(err)
	}
	defer outFile.Close()

	// Create a zip writer on top of the file writer
	zipWriter := zip.NewWriter(outFile)

	//update document data content with path and cksum
	for i, docMeta := range metadata.Documents {
		document := *inBnFilename + "/documents/" + docMeta.Filename
		content := Content{}
		err = filepath.Walk(document, func(path string, fileInfo os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if !fileInfo.IsDir() {
				content.Filetype = "application/octet-stream"
				content.Filename = fileInfo.Name()
				content.Path = "documents"
				content.Size = fmt.Sprint(fileInfo.Size())
				contentFileData, err := ioutil.ReadFile(path)
				if err != nil {
					log.Println("Error occurred during reading document file : " + path)
					log.Fatal(err)
					return err
				}
				checkSum := sha256.Sum256(contentFileData)
				if *corruptedCheckSum {
					checkSum[0] = 1
				}
				content.Digest = fmt.Sprintf("sha256:%x", checkSum)
				fileWriter, err := zipWriter.Create(content.Path + string(filepath.Separator) + fileInfo.Name())
				if err != nil {
					log.Println("Error occurred during creating document file inside zip file : " + path)
					log.Fatal(err)
					return err
				}
				_, err = fileWriter.Write([]byte(contentFileData))
				if err != nil {
					log.Println("Error occurred during writing document file inside zip file : " + path)
					log.Fatal(err)
					return err
				}
			}
			return nil
		})
		if err != nil {
			log.Println("Error in processing the document for the artifact : " + document)
			log.Fatal(err)
			return
		}
		metadata.Documents[i] = content
	}

	//update artifact data content with path and cksum
	for i, appMeta := range metadata.Data {
		//update content for all artifacts
		artifact := *inBnFilename + "/content/" + appMeta.Name
		//converting artifact name to lowercase and replacing underscore with hyphen
		artifactName := strings.ToLower(appMeta.Name)
		artifactName = strings.ReplaceAll(artifactName, "_", "-")

		validationResult = IsQualifiedName(artifactName)
	    if len(validationResult) <=0 {
		   log.Println(artifactName + " is a valid name for an Artifact.")

	    } else {
		  log.Println(artifactName + " is not a valid name for an Artifact. Artifact name should be a valid dns value.")
		  log.Println(validationResult)
		  return
	    }

		contents := []Content{}
		err = filepath.Walk(artifact, func(path string, fileInfo os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if !fileInfo.IsDir() {
				content := Content{}
				content.Filetype = "application/octet-stream"
				content.Filename = fileInfo.Name()
				relPath, err := filepath.Rel(*inBnFilename+"/content/"+appMeta.Name, path)
				if err != nil {
					log.Println("Error occurred while extracting relative part : " + path)
					log.Fatal(err)
					return err
				}
				var contentPath string
				if filepath.Dir(relPath) != "." {
					contentPath = "content/" + artifactName + string(filepath.Separator) + filepath.Dir(relPath)
				} else {
					contentPath = "content/" + artifactName
				}

				content.Path = contentPath
				content.Size = fmt.Sprint(fileInfo.Size())
				contentFileData, err := ioutil.ReadFile(path)
				if err != nil {
					log.Println("Error occurred during reading content file : " + path)
					log.Fatal(err)
					return err
				}

				checkSum := sha256.Sum256(contentFileData)
				if *corruptedCheckSum {
					checkSum[0] = 1
				}
				content.Digest = fmt.Sprintf("sha256:%x", checkSum)

				//adding to content
				contents = append(contents, content)

				fileWriter, err := zipWriter.Create(contentPath + string(filepath.Separator) + fileInfo.Name())
				if err != nil {
					log.Println("Error occurred during creating content file inside zip file : " + path)
					log.Fatal(err)
					return err
				}
				_, err = fileWriter.Write([]byte(contentFileData))
				if err != nil {
					log.Println("Error occurred during writing content file inside zip file : " + path)
					log.Fatal(err)
					return err
				}
			}
			return nil
		})
		if err != nil {
			log.Println("Error in processing the content for the artifact : " + artifact)
			log.Fatal(err)
			return
		}

		metadata.Data[i].Name = artifactName
		metadata.Data[i].Content = contents
		if metadata.Data[i].Dependencies == nil {
			dependencies := []Dependencies{}
			metadata.Data[i].Dependencies = dependencies
		}
	}

	metadataJsonByte, _ := json.MarshalIndent(metadata, "", " ")

	if *corruptedCheckSum {
		log.Println("Generating metadata.json with corrupted checksum")
	}
	//writing the metadata.json
	metaDataFileWriter, err := zipWriter.Create("metadata.json")
	if err != nil {
		log.Println("Error in adding metadata.json file to zip")
		log.Fatal(err)
	}
	_, err = metaDataFileWriter.Write([]byte(metadataJsonByte))
	if err != nil {
		log.Println("Error in writing the metadata file into zip")
		log.Fatal(err)
	}

	if !*unsigned {
		signedMetadata := []byte{}
		if *useNokiaRDKey {
			log.Println("Generating Nokia R&D signature file")
			digest := fmt.Sprintf("%x", sha256.Sum256(metadataJsonByte))
			response, err := http.Post("http://100.120.29.40:10000/sign", "text/plain;charset=UTF-8", strings.NewReader(digest))
			if err == nil {
				defer response.Body.Close()
				signedMetadata, err = ioutil.ReadAll(response.Body)
			} else {
				log.Println("Unable to signed with Nokia R&D Key")
				log.Fatal(err)
				return
			}
		} else {
			log.Println("Generating signature file with User Keys")
			//generate the signature
			privateKey, err := ReadPrivateKeyFile(*pkFilename)
			if err != nil {
				log.Println("Unable to read the private key file")
				log.Fatal(err)
				return
			}

			signedMetadata, err = Sign(privateKey, metadataJsonByte)
			if err != nil {
				log.Println("Unable to sign the metadata file")
				log.Fatal(err)
				return
			}
		}
		log.Println("Creating artifact bundle zip file")
		//writing the signature file
		signatureFileWriter, err := zipWriter.Create("signature.txt")
		if err != nil {
			log.Println("Error in adding signature.txt file to zip")
			log.Fatal(err)
		}

		_, err = signatureFileWriter.Write([]byte(signedMetadata))
		if err != nil {
			log.Println("Error in writing the metadata file into zip")
			log.Fatal(err)
		}
	}
	// Clean up
	err = zipWriter.Close()
	if err != nil {
		log.Println("Error in writing the zip file")
		log.Fatal(err)
	}

	log.Println("Artifact Bundle creation completed and bundle is " + generatedBundleName)

}

func ReadPrivateKeyFile(filepath string) (privateKey *rsa.PrivateKey, err error) {
	privPEM, err := ioutil.ReadFile(filepath)
	if err != nil {
		return
	}
	privateKey, err = ReadPrivateKey(privPEM)
	return
}

func ReadPrivateKey(privateKeyData []byte) (privateKey *rsa.PrivateKey, err error) {
	block, _ := pem.Decode(privateKeyData)
	if block == nil {
		err = errors.New("failed to parse PEM block containing the key")
		return
	}

	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	privateKey = key.(*rsa.PrivateKey)

	return privateKey, err
}

func Sign(privateKey *rsa.PrivateKey, plaintext []byte) (signature []byte, err error) {
	digest := sha256.Sum256(plaintext)
	str := fmt.Sprintf("%x", digest)
	str = strings.ToUpper(str)
	uDigest := []byte(str)
	digest = sha256.Sum256(uDigest)
	signed, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, digest[:])
	if err != nil {
		panic(err)
	}
	hexSigned := make([]byte, hex.EncodedLen(len(signed)))
	hex.Encode(hexSigned, []byte(signed))
	return hexSigned, err
}


const dns1123LabelFmt string = "[a-z0-9]([-a-z0-9]*[a-z0-9])?"
const dns1123LabelErrMsg string = "a lowercase RFC 1123 label must consist of lower case alphanumeric characters or '-', and must start and end with an alphanumeric character"
const dns1123SubdomainFmt string = dns1123LabelFmt + "(\\." + dns1123LabelFmt + ")*"
const dns1123SubdomainErrorMsg string = "a lowercase RFC 1123 subdomain must consist of lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character"

const DNS1123SubdomainMaxLength int = 253

var dns1123SubdomainRegexp = regexp.MustCompile("^" + dns1123SubdomainFmt + "$")

const qnameCharFmt string = "[A-Za-z0-9]"
const qnameExtCharFmt string = "[-A-Za-z0-9_.]"
const qualifiedNameFmt string = "(" + qnameCharFmt + qnameExtCharFmt + "*)?" + qnameCharFmt
const qualifiedNameErrMsg string = "must consist of alphanumeric characters, '-', '_' or '.', and must start and end with an alphanumeric character"
const qualifiedNameMaxLength int = 63

var qualifiedNameRegexp = regexp.MustCompile("^" + qualifiedNameFmt + "$")

func IsQualifiedName(value string) []string {
	var errs []string
	parts := strings.Split(value, "/")
	var name string
	switch len(parts) {
	case 1:
		name = parts[0]
	case 2:
		var prefix string
		prefix, name = parts[0], parts[1]
		if len(prefix) == 0 {
			errs = append(errs, "prefix part "+EmptyError())
		} else if msgs := IsDNS1123Subdomain(prefix); len(msgs) != 0 {
			errs = append(errs, prefixEach(msgs, "prefix part ")...)
		}
	default:
		return append(errs, "a qualified name "+RegexError(qualifiedNameErrMsg, qualifiedNameFmt, "MyName", "my.name", "123-abc")+
			" with an optional DNS subdomain prefix and '/' (e.g. 'example.com/MyName')")
	}

	if len(name) == 0 {
		errs = append(errs, "name part "+EmptyError())
	} else if len(name) > qualifiedNameMaxLength {
		errs = append(errs, "name part "+MaxLenError(qualifiedNameMaxLength))
	}
	if !qualifiedNameRegexp.MatchString(name) {
		errs = append(errs, "name part "+RegexError(qualifiedNameErrMsg, qualifiedNameFmt, "MyName", "my.name", "123-abc"))
	}
	return errs
}

func IsDNS1123Subdomain(value string) []string {
	var errs []string
	if len(value) > DNS1123SubdomainMaxLength {
		errs = append(errs, MaxLenError(DNS1123SubdomainMaxLength))
	}
	if !dns1123SubdomainRegexp.MatchString(value) {
		errs = append(errs, RegexError(dns1123SubdomainErrorMsg, dns1123SubdomainFmt, "example.com"))
	}
	return errs
}

func EmptyError() string {
	return "must be non-empty"
}

func MaxLenError(length int) string {
	return fmt.Sprintf("must be no more than %d characters", length)
}

// RegexError returns a string explanation of a regex validation failure.
func RegexError(msg string, fmt string, examples ...string) string {
	if len(examples) == 0 {
		return msg + " (regex used for validation is '" + fmt + "')"
	}
	msg += " (e.g. "
	for i := range examples {
		if i > 0 {
			msg += " or "
		}
		msg += "'" + examples[i] + "', "
	}
	msg += "regex used for validation is '" + fmt + "')"
	return msg
}

func prefixEach(msgs []string, prefix string) []string {
	for i := range msgs {
		msgs[i] = prefix + msgs[i]
	}
	return msgs
}

