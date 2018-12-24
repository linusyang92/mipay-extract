package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path"
	"strings"
	"time"

	"github.com/google/go-github/github"
	gover "github.com/mcuadros/go-version"
	"github.com/mmcdole/gofeed"
	"github.com/yhat/scrape"
	"golang.org/x/net/html"
	"golang.org/x/net/html/atom"
	"golang.org/x/oauth2"
)

const (
	FakeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_3) " +
		"AppleWebKit/537.36 (KHTML, like Gecko) " +
		"Chrome/63.0.3239.132 Safari/537.36"
	MiuiUpdateUrl  = "https://www.miui.com/download-337.html"
	GqReleaseUrl   = "https://miui.dedyk.gq"
	SfReleaseModel = "MIMix2"
	SfReleaseUrl   = "https://sourceforge.net/projects" +
		"/xiaomi-eu-multilang-miui-roms/rss?" +
		"path=/xiaomi.eu/MIUI-WEEKLY-RELEASES"
	SfDownBaseUrl = "https://jaist.dl.sourceforge.net/" +
		"project/xiaomi-eu-multilang-miui-roms"
	GithubOwner = "linusyang92"
	GithubRepo  = "mipay-extract"
	GithubPath  = "deploy.sh"
	GithubEmail = "32575696+linusyang92@users.noreply.github.com"
)

type MyLogger struct {
	logger *log.Logger
}

func (m *MyLogger) Error(prompt string, e error) {
	if e == nil {
		m.Log("[Error] %s", prompt)
	} else {
		m.Log("[Error] %s: %s", prompt, e.Error())
	}
}

func (m *MyLogger) Log(format string, v ...interface{}) {
	m.logger.Printf(format+"\n", v...)
}

var logger = &MyLogger{
	logger: log.New(os.Stderr, "", log.LstdFlags),
}

func fetchUrl(url string) ([]byte, error) {
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{
		Transport: tr,
		Timeout:   10 * time.Second,
	}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Add("User-Agent", FakeUserAgent)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return ioutil.ReadAll(resp.Body)
}

func getMiui() (version string, url string) {
	logger.Log("Fetching MIUI version info...")
	version = "0.0.0"
	url = ""
	b, err := fetchUrl(MiuiUpdateUrl)
	if err != nil {
		logger.Error("Cannot fetch MIUI rom page", err)
		return
	}
	root, err := html.Parse(bytes.NewReader(b))
	if err != nil {
		logger.Error("Failed to parse html", err)
		return
	}
	matcher := func(n *html.Node) bool {
		if n.DataAtom == atom.A {
			return scrape.Attr(n, "class") == "download_btn"
		}
		return false
	}
	r := scrape.FindAll(root, matcher)
	if len(r) > 0 {
		url = scrape.Attr(r[len(r)-1], "href")
		paths := strings.Split(url, "/")
		if len(paths) > 0 {
			f := strings.Split(paths[len(paths)-1], "_")
			if len(f) > 2 {
				version = f[2]
			}
		}
	}
	logger.Log("MIUI version: %s", version)
	return
}

func getEu(miuiVer string) (version string, url string) {
	logger.Log("Fetching xiaomi.eu version info...")
	version = "0.0.0"
	url = ""
	p := gofeed.NewParser()
	feed, err := p.ParseURL(SfReleaseUrl + "/" + miuiVer)
	if err != nil {
		logger.Error("Failed to parse rss", err)
		return
	}
	for _, item := range feed.Items {
		if strings.Contains(item.Title, SfReleaseModel+"_") {
			url = SfDownBaseUrl + item.Title
			f := strings.Split(item.Title, "/")
			if len(f) > 0 {
				p := strings.Split(f[len(f)-1], "_")
				if len(p) > 3 {
					version = p[3]
				}
			}
			break
		}
	}
	logger.Log("EU version: %s", version)
	return
}

func getEuAlt(miuiVer string) (version string, url string) {
	logger.Log("Fetching xiaomi.eu version (alternative)...")
	version = "0.0.0"
	url = ""
	baseUrl := GqReleaseUrl + "/" + miuiVer + "/"
	b, err := fetchUrl(baseUrl)
	if err != nil {
		logger.Error("Cannot fetch "+GqReleaseUrl, err)
		return
	}
	root, err := html.Parse(bytes.NewReader(b))
	if err != nil {
		logger.Error("Failed to parse html", err)
		return
	}
	matcher := func(n *html.Node) bool {
		if n.DataAtom == atom.A {
			return strings.Contains(scrape.Attr(n, "href"), SfReleaseModel+"_")
		}
		return false
	}
	r := scrape.FindAll(root, matcher)
	if len(r) > 0 {
		f := scrape.Attr(r[len(r)-1], "href")
		url = baseUrl + f
		p := strings.Split(f, "_")
		if len(p) > 3 {
			version = p[3]
		}
	}
	logger.Log("EU version: %s", version)
	return
}

func getVersion(deploy string) (version string) {
	version = "0.0.0"
	scanner := bufio.NewScanner(strings.NewReader(deploy))
	for scanner.Scan() {
		t := scanner.Text()
		if strings.Contains(t, "bigota.d.miui.com") {
			f := strings.Split(t, "_")
			if len(f) > 2 {
				version = f[2]
			}
			break
		}
	}
	return
}

func newDeployFile(version, miuiUrl, euUrl string, orig string) []byte {
	res := bytes.NewBufferString("")
	scanner := bufio.NewScanner(strings.NewReader(orig))
	for scanner.Scan() {
		t := scanner.Text()
		if strings.Contains(t, "bigota.d.miui.com") {
			res.WriteString("'" + miuiUrl + "'")
		} else if strings.Contains(t, "EU_VER=") {
			res.WriteString("EU_VER=" + version)
		} else if strings.Contains(t, "dl.sourceforge.net") {
			res.WriteString("'" + euUrl + "'")
		} else {
			res.WriteString(t)
		}
		res.WriteString("\n")
	}
	return res.Bytes()
}

func getNewDeploy(currentVer, currentDeploy string,
	force bool) (version string, deploy []byte, err error) {
	miuiVer, miuiUrl := getMiui()
	euVer, euUrl := "", ""
	version = currentVer
	deploy = []byte(currentDeploy)
	err = nil
	if gover.Compare(miuiVer, currentVer, ">") || force {
		version = miuiVer
		euVer, euUrl = getEu(miuiVer)
		if len(euUrl) == 0 {
			euVer, euUrl = getEuAlt(miuiVer)
		}
		if euVer == miuiVer || force {
			deploy = newDeployFile(miuiVer, miuiUrl, euUrl, currentDeploy)
		}
	}
	if gover.Compare(miuiVer, currentVer, "<=") {
		err = errors.New(fmt.Sprintf("MIUI China (current: %s)", miuiVer))
	} else if euVer != miuiVer {
		err = errors.New(fmt.Sprintf("xiaomi.eu (current: %s)", euVer))
	}
	return
}

func updateGithub(token string) (retCode int) {
	ctx := context.Background()
	ts := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: token},
	)
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	// Fetch original file
	logger.Log("Github - fetching repo...")
	branch := "master"
	gopt := github.RepositoryContentGetOptions{
		Ref: branch,
	}
	content, _, _, err := client.Repositories.GetContents(ctx, GithubOwner,
		GithubRepo, GithubPath, &gopt)
	if err != nil {
		logger.Error("Github - failed to fetch repo", err)
		return 1
	}
	orig, err := content.GetContent()
	if err != nil {
		logger.Error("Github - failed to get "+GithubPath, err)
		return 1
	}
	ver := getVersion(orig)
	logger.Log("Github - current version: %s", ver)

	// Get latest rom version
	version, deploy, err := getNewDeploy(ver, orig, false)
	if err != nil {
		logger.Log("No updates found for %s", err.Error())
		return 0
	} else {
		logger.Log("New version found: %s", version)
		logger.Log("Updating Github repo...")
	}

	// Update new file
	date := time.Now()
	name := GithubOwner
	email := GithubEmail
	author := github.CommitAuthor{
		Date:  &date,
		Name:  &name,
		Email: &email,
	}
	message := "Update to " + version
	SHA := content.GetSHA()
	uopt := github.RepositoryContentFileOptions{
		Message: &message,
		Content: deploy,
		SHA:     &SHA,
		Branch:  &branch,
		Author:  &author,
	}
	resp, _, err := client.Repositories.UpdateFile(ctx, GithubOwner,
		GithubRepo, GithubPath, &uopt)
	if err != nil {
		logger.Error("Github - failed to update repo", err)
		return 1
	}

	// Create tag for new commit
	newSHA := resp.GetSHA()
	obj := github.GitObject{
		SHA: &newSHA,
	}
	newTag := "refs/tags/" + version
	ref := github.Reference{
		Ref:    &newTag,
		Object: &obj,
	}
	_, _, err = client.Git.CreateRef(ctx, GithubOwner, GithubRepo, &ref)
	if err != nil {
		logger.Error("Github - failed to create new tag", err)
		return 1
	}

	logger.Log("Github repo updated")
	return 0
}

func main() {
	ret := 0
	defer func() {
		os.Exit(ret)
	}()
	token := ""
	if len(os.Args) > 1 {
		token = os.Args[1]
	} else {
		fmt.Fprintf(os.Stderr, "Usage: %s <Github API token>\n", path.Base(os.Args[0]))
		ret = 1
		return
	}
	logger.Log("MIUI update checker - Device: %v", SfReleaseModel)
	ret = updateGithub(token)
}
