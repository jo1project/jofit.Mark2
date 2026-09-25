package com.jofit.autobooking.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jofit.autobooking.model.Course
import com.jofit.autobooking.model.CourseTemplate
import java.io.File
import kotlinx.coroutines.CancellationException

/**
 * Loads the weekly recurring course schedule at launch and on pull-to-refresh — from the
 * backend once an admin has edited it there, else from `courses.json` in the repo (raw GitHub
 * URL) — expanding each recurring slot into concrete instances for the next 4 weeks. Caches the
 * raw templates on disk and falls back to a small bundled default if no fetch has ever succeeded.
 */
class CourseStore(context: Context, private val client: BackendClient) {
    private val cacheFile = File(context.filesDir, "courses_cache.json")

    var templates by mutableStateOf(loadCache() ?: CourseTemplate.fallback)
        private set
    var courses by mutableStateOf(resolve(templates))
        private set

    suspend fun refresh() = detached {
        try {
            apply(fetchTemplates())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Re-resolve the existing templates in case the day rolled over since launch.
            courses = resolve(templates)
        }
    }

    /** Admin only: saves the list on the backend (everyone's app picks it up on their next refresh), then adopts it locally. */
    suspend fun save(new: List<CourseTemplate>, pin: String) = detached {
        client.saveCourses(new, pin)
        apply(new)
    }

    /**
     * The backend's list is the source of truth once an admin has saved one; until then it's
     * empty and the repo's `courses.json` is used. A backend error deliberately doesn't fall
     * through to the repo list — that could be older than the shared one we have cached.
     */
    private suspend fun fetchTemplates(): List<CourseTemplate> {
        val shared = client.listCourses()
        if (shared.isNotEmpty()) return shared
        return CourseTemplates.parse(httpRequest(REMOTE_URL)).also { require(it.isNotEmpty()) }
    }

    private fun apply(new: List<CourseTemplate>) {
        templates = new
        courses = resolve(new)
        runCatching { cacheFile.writeText(CourseTemplates.toJson(new)) }
    }

    private fun loadCache(): List<CourseTemplate>? =
        runCatching { CourseTemplates.parse(cacheFile.readText()) }.getOrNull()

    private fun resolve(templates: List<CourseTemplate>): List<Course> =
        templates.flatMap { it.resolvedCourses(WEEKS_AHEAD) }
            // id as a final tiebreaker: multiple classrooms can share the same date+time.
            .sortedWith(compareBy({ it.date }, { it.time }, { it.id }))

    private companion object {
        const val WEEKS_AHEAD = 4
        const val REMOTE_URL = "https://raw.githubusercontent.com/jo1project/jofit.Mark2/main/courses.json"
    }
}
