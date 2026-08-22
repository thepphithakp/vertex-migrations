// =============================================================================
// Jenkins pipeline สำหรับ vertex-migrations
// =============================================================================
// เขียนเป็น declarative pipeline มาตรฐาน ไม่ผูกกับ shared library ของที่ไหน
// ต้องการแค่ docker, kubectl, helm บน agent
//
// ต่างจาก jenkins/*.groovy ของ oba-flyway-mas-db ที่ใช้ k8s_pod_build จาก
// lib-build-jenkinsk8s-docker ซึ่งเป็น library เฉพาะขององค์กร
// ถ้าย้ายมาใช้ Jenkins ที่มี library นั้น ให้แทน stage Build/Push ด้วย
// k8s_pod_build ได้เลย ส่วน stage Deploy ยังใช้เหมือนเดิม
//
// Credentials ที่ต้องตั้งใน Jenkins:
//   registry-creds  (Username/Password) — สำหรับ push image
//   kubeconfig-<env> (Secret file)      — kubeconfig ที่จำกัดสิทธิ์ namespace เดียว
// =============================================================================

pipeline {
    agent any

    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['production'],
            description: 'environment ที่จะ deploy'
        )
        choice(
            name: 'FLYWAY_COMMAND',
            choices: ['migrate', 'info', 'validate', 'repair'],
            description: '''คำสั่ง Flyway
                info     = ดูสถานะเฉยๆ ไม่แก้อะไร (ใช้ตรวจก่อนลงมือจริง)
                validate = ตรวจ checksum ว่าไฟล์ที่ apply ไปแล้วไม่ถูกแก้
                repair   = ซ่อม history table หลัง migration ล้ม (ไม่ย้อนข้อมูล)'''
        )
        string(
            name: 'SERVICES',
            defaultValue: 'all',
            description: 'service ที่จะรัน คั่นด้วย comma หรือ all'
        )
        booleanParam(
            name: 'SKIP_DEPLOY',
            defaultValue: false,
            description: 'build image อย่างเดียว ไม่รัน migration'
        )
    }

    environment {
        REGISTRY   = 'ghcr.io'
        IMAGE_NAME = 'thepphithakp/vertex-migrations'
        IMAGE_TAG  = "sha-${env.GIT_COMMIT}"
        NAMESPACE  = 'vertex'
    }

    options {
        timestamps()
        disableConcurrentBuilds()   // migration ห้ามรันพร้อมกันหลาย build
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    stages {
        stage('Lint') {
            steps {
                // ตรวจกฎที่เคยทำให้พลาดมาแล้วจริง เช่น CHECK constraint
                // กับค่าที่แก้ผ่าน UI ได้ และชื่อไฟล์ R__ ที่ไม่มีเลขนำหน้า
                sh 'bash scripts/lint.sh'
            }
        }

        stage('Build & Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'registry-creds',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo "$REG_PASS" | docker login "$REGISTRY" -u "$REG_USER" --password-stdin
                        docker build --platform linux/amd64 \
                            -t "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" \
                            -t "$REGISTRY/$IMAGE_NAME:latest" .
                        docker push "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
                        docker push "$REGISTRY/$IMAGE_NAME:latest"
                    '''
                }
            }
        }

        stage('Deploy') {
            when { expression { !params.SKIP_DEPLOY } }
            steps {
                withCredentials([file(
                    credentialsId: "kubeconfig-${params.ENVIRONMENT}",
                    variable: 'KUBECONFIG'
                )]) {
                    script {
                        // แปลงรายชื่อ service เป็น --set services[i].enabled
                        def all = ['auth', 'pet']
                        def want = params.SERVICES.trim()
                        def flags = all.indexed().collect { i, s ->
                            def on = (want == 'all' || want.split(',')*.trim().contains(s))
                            "--set services[${i}].enabled=${on}"
                        }.join(' ')

                        // ⚠️ ไม่ใช้ --wait
                        // helm --wait คืนค่าก่อน Job ทำงานเสร็จจริง (เจอมาแล้ว)
                        // ให้ stage Verify รอเองด้วย label revision แทน
                        sh """
                            helm upgrade --install vertex-migrations ./helm/vertex-migrations \
                                --namespace "$NAMESPACE" \
                                -f values-prod.yaml \
                                --set image.tag="$IMAGE_TAG" \
                                --set command="${params.FLYWAY_COMMAND}" \
                                ${flags}
                        """
                        env.HELM_REVISION = sh(
                            script: "helm get metadata vertex-migrations -n ${NAMESPACE} -o json | jq -r .version",
                            returnStdout: true
                        ).trim()
                        echo "release revision = ${env.HELM_REVISION}"
                    }
                }
            }
        }

        stage('Verify') {
            when { expression { !params.SKIP_DEPLOY } }
            steps {
                withCredentials([file(
                    credentialsId: "kubeconfig-${params.ENVIRONMENT}",
                    variable: 'KUBECONFIG'
                )]) {
                    // Job สร้างสำเร็จไม่ได้แปลว่า Flyway ข้างในสำเร็จ ต้องรอแล้วตรวจ status
                    // เลือก Job ด้วย label revision ไม่ใช่ tail -N ซึ่งพังเมื่อจำนวน service เปลี่ยน
                    sh '''
                        sel="app.kubernetes.io/component=migration,vertex.io/release-revision=$HELM_REVISION"
                        deadline=$(( $(date +%s) + 600 ))

                        jobs=$(kubectl get jobs -n "$NAMESPACE" -l "$sel" -o jsonpath='{.items[*].metadata.name}')
                        [ -n "$jobs" ] || { echo "🔴 ไม่พบ Job ของ revision $HELM_REVISION"; exit 1; }

                        for job in $jobs; do
                            while :; do
                                ok=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')
                                bad=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.failed}')
                                [ "${ok:-0}" -ge 1 ] 2>/dev/null && break
                                limit=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.spec.backoffLimit}')
                                [ "${bad:-0}" -gt "$limit" ] && break
                                [ "$(date +%s)" -gt "$deadline" ] && break
                                sleep 5
                            done
                        done

                        failed=0
                        for job in $jobs; do
                            echo "===== $job ====="
                            kubectl logs -n "$NAMESPACE" "job/$job" --tail=200 || true
                            ok=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')
                            if [ "${ok:-0}" -lt 1 ] 2>/dev/null; then
                                echo "🔴 $job ไม่สำเร็จ"
                                failed=1
                            fi
                        done
                        exit $failed
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ migration สำเร็จ — image $IMAGE_TAG"
            echo "⚠️ อย่าลืมอัปเดต migration.image.tag ใน helm values ของ service ที่เกี่ยวข้อง"
        }
        failure {
            echo "🔴 migration ล้มเหลว — อ่าน log ของ Job ด้านบน"
            echo "   ถ้า Flyway mark migration เป็น failed ให้รันซ้ำด้วย FLYWAY_COMMAND=repair"
            echo "   ⚠️ repair ซ่อมแค่ history table ไม่ได้ย้อนข้อมูลที่เปลี่ยนไปแล้ว"
        }
        always {
            sh 'docker logout "$REGISTRY" || true'
        }
    }
}
