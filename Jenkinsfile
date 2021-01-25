@Library('dst-shared@release/shasta-1.4') _
 
dockerBuildPipeline {
    app = "ims-sshd"
    name = "cms-ims-sshd"
    description = "Cray image management service SSH container"
    repository = "cray"
    imagePrefix = "cray"
    product = "csm"
    sendEvents = ["IMS"]

    githubPushRepo = "Cray-HPE/ims-sshd"
    /*
        By default all branches are pushed to GitHub

        Optionally, to limit which branches are pushed, add a githubPushBranches regex variable
        Examples:
        githubPushBranches =  /master/ # Only push the master branch
        
        In this case, we push bugfix, feature, hot fix, master, and release branches

        NOTE: If this Jenkinsfile is removed, the a Jenkinsfile.github file must be created
        to do this push. See the cray-product-install-charts repo for an example.
    */
    githubPushBranches =  /(bugfix\/.*|feature\/.*|hotfix\/.*|master|release\/.*)/ 
}
