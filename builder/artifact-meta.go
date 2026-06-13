package main

type Meta struct {
	Header `json:"meta-data-header"`
	Data   []Data `json:"artifact-meta-data"`
}

type Header struct {
	Name          string `json:"name"`
	Version       string `json:"version"`
	BuildNumber   string `json:"buildNumber"`
	FormatVersion string `json:"formatVersion"`
	CreatedBy     string `json:"createdBy"`
	CreationDate  string `json:"creationDate"`
	Title         string `json:"title"`
	Description   string `json:"description"`
	SelectiveInstall *bool   `json:"selectiveInstall,omitempty"`
	Documents        []Content `json:"documents,omitempty"`
}

type Data struct {
	TargetApplication        string    `json:"targetApplication"`
	ApplicationCompatibility string    `json:"applicationCompatibility"`
	Version                  string    `json:"version"`
	Name                     string    `json:"name"`
	Content                  []Content `json:"artifact-content"`
	Dependencies             []Dependencies `json:"dependencies"`
}

type Content struct {
	Filetype string `json:"type"`
	Size     string `json:"size"`
	Path     string `json:"path"`
	Filename string `json:"fileName"`
	Digest   string `json:"digest"`
}


type Dependencies struct {
	ArtifactName string `json:"artifactName"`
	ArtifactVersion     string `json:"artifactVersion"`
}
